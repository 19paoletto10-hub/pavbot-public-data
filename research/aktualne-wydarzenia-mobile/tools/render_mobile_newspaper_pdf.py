#!/usr/bin/env python3
"""Render a mobile newspaper PDF for the Pavbot current-events workflow."""

import argparse
import re
import sys
from dataclasses import dataclass
from datetime import datetime
from html import escape
from pathlib import Path

from reportlab.lib import colors
from reportlab.lib.enums import TA_CENTER, TA_LEFT
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import mm
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import (
    HRFlowable,
    KeepTogether,
    ListFlowable,
    ListItem,
    PageBreak,
    Paragraph,
    SimpleDocTemplate,
    Spacer,
    Table,
    TableStyle,
)

REPO_ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(REPO_ROOT / "scripts"))

from pavbot_pdf_theme import (  # noqa: E402
    AMBER,
    BORDER as THEME_BORDER,
    CONTENT_WIDTH,
    FONT_BOLD as THEME_FONT_BOLD,
    FONT_REGULAR as THEME_FONT_REGULAR,
    MOBILE_PAGE_SIZE,
    PAGE_MARGIN_BOTTOM,
    PAGE_MARGIN_TOP,
    PAGE_MARGIN_X,
    PAPER_WARM,
    draw_mobile_page,
)


PAGE_SIZE = MOBILE_PAGE_SIZE
REQUIRED_SECTIONS = ("Ogólne", "Polska", "Polityka", "Sprawy zagraniczne", "Technologia")

INK = colors.HexColor("#111827")
MUTED = colors.HexColor("#475569")
PAPER = PAPER_WARM
PAPER_ALT = colors.HexColor("#F8FAFC")
RULE = colors.HexColor("#0F172A")
ACCENT = colors.HexColor("#B91C1C")
ACCENT_DARK = colors.HexColor("#7F1D1D")
GOLD = colors.HexColor("#D97706")
LINK = colors.HexColor("#1D4ED8")
BORDER = THEME_BORDER


@dataclass
class Article:
    section: str
    title: str
    lead: str
    facts: list[str]
    analysis: str


def fail(message: str, code: int = 1) -> None:
    print(message, file=sys.stderr)
    raise SystemExit(code)


def register_fonts() -> tuple[str, str]:
    regular_candidates = [
        "/System/Library/Fonts/Supplemental/Arial Unicode.ttf",
        "/System/Library/Fonts/Supplemental/Arial.ttf",
        "/Library/Fonts/Arial.ttf",
        "/System/Library/Fonts/Supplemental/DejaVu Sans.ttf",
    ]
    bold_candidates = [
        "/System/Library/Fonts/Supplemental/Arial Bold.ttf",
        "/Library/Fonts/Arial Bold.ttf",
        "/System/Library/Fonts/Supplemental/DejaVu Sans Bold.ttf",
    ]
    regular = next((Path(path) for path in regular_candidates if Path(path).is_file()), None)
    bold = next((Path(path) for path in bold_candidates if Path(path).is_file()), None)
    if regular:
        pdfmetrics.registerFont(TTFont("PavbotNews", str(regular)))
        if bold:
            pdfmetrics.registerFont(TTFont("PavbotNews-Bold", str(bold)))
            return "PavbotNews", "PavbotNews-Bold"
        return "PavbotNews", "PavbotNews"
    return "Helvetica", "Helvetica-Bold"


FONT_REGULAR, FONT_BOLD = THEME_FONT_REGULAR, THEME_FONT_BOLD


def read_text(path: Path) -> str:
    if not path.is_file():
        fail(f"missing file: {path}", 66)
    return path.read_text(encoding="utf-8")


def markdown_inline(text: str) -> str:
    escaped = escape(re.sub(r"\s+", " ", text).strip())
    escaped = re.sub(r"\*\*(.+?)\*\*", r"<b>\1</b>", escaped)

    def link_repl(match: re.Match[str]) -> str:
        label = escape(match.group(1))
        url = escape(match.group(2), quote=True)
        return f'<a href="{url}"><font color="#1D4ED8">{label}</font></a>'

    return re.sub(r"\[([^\]]+)\]\((https?://[^)]+)\)", link_repl, escaped)


def source_links(text: str) -> list[tuple[str, str]]:
    return [(label.strip(), url.strip()) for label, url in re.findall(r"\[([^\]]+)\]\((https?://[^)]+)\)", text)]


def split_metadata(markdown_text: str) -> tuple[str, dict[str, str]]:
    title = "Pavbot Aktualne Wydarzenia"
    metadata: dict[str, str] = {}
    for raw in markdown_text.splitlines():
        line = raw.strip()
        if line.startswith("# "):
            title = line[2:].strip()
            continue
        if ":" in line and not line.startswith("- "):
            key, value = line.split(":", 1)
            if key.lower() in {"date", "status"}:
                metadata[key.lower()] = value.strip()
    return title, metadata


def parse_newspaper_articles(markdown_text: str) -> dict[str, list[Article]]:
    articles: dict[str, list[Article]] = {section: [] for section in REQUIRED_SECTIONS}
    current_section: str | None = None
    current: Article | None = None
    mode: str | None = None

    def flush() -> None:
        nonlocal current
        if current is not None:
            articles.setdefault(current.section, []).append(current)
            current = None

    for raw in markdown_text.splitlines():
        line = raw.rstrip()
        stripped = line.strip()
        if not stripped:
            continue
        if stripped.startswith("### ") and not stripped.startswith("#### "):
            flush()
            candidate = stripped[4:].strip()
            current_section = candidate if candidate in REQUIRED_SECTIONS else None
            mode = None
            continue
        if stripped.startswith("#### ") and current_section:
            flush()
            current = Article(section=current_section, title=stripped[5:].strip(), lead="", facts=[], analysis="")
            mode = None
            continue
        if current is None:
            continue
        if stripped.startswith("Lead:"):
            current.lead = stripped.split(":", 1)[1].strip()
            mode = "lead"
            continue
        if stripped == "Fakty:":
            mode = "facts"
            continue
        if stripped.startswith("Analiza:"):
            current.analysis = stripped.split(":", 1)[1].strip()
            mode = "analysis"
            continue
        if stripped.startswith("- ") and mode == "facts":
            current.facts.append(stripped[2:].strip())
            continue
        if mode == "lead":
            current.lead = f"{current.lead} {stripped}".strip()
        elif mode == "analysis":
            current.analysis = f"{current.analysis} {stripped}".strip()
        elif mode == "facts" and current.facts:
            current.facts[-1] = f"{current.facts[-1]} {stripped}".strip()

    flush()
    for section in REQUIRED_SECTIONS:
        if not articles.get(section):
            articles[section] = [
                Article(
                    section=section,
                    title="Brak materialnej zmiany",
                    lead="W tej sekcji nie wykryto nowego faktu o wysokiej wadze publicznej.",
                    facts=["Brak materialnej zmiany po sprawdzeniu źródeł wskazanych w raporcie."],
                    analysis="Sekcja pozostaje w wydaniu jako kontrola kompletności workflow.",
                )
            ]
    return articles


def build_styles() -> dict[str, ParagraphStyle]:
    base = getSampleStyleSheet()
    return {
        "kicker": ParagraphStyle(
            "NewsKicker",
            parent=base["Normal"],
            fontName=FONT_BOLD,
            fontSize=8,
            leading=10,
            alignment=TA_CENTER,
            textColor=ACCENT_DARK,
            spaceAfter=2,
        ),
        "masthead": ParagraphStyle(
            "NewsMasthead",
            parent=base["Title"],
            fontName=FONT_BOLD,
            fontSize=27,
            leading=30,
            alignment=TA_CENTER,
            textColor=RULE,
            spaceAfter=2,
            splitLongWords=True,
        ),
        "subtitle": ParagraphStyle(
            "NewsSubtitle",
            parent=base["Normal"],
            fontName=FONT_REGULAR,
            fontSize=7.8,
            leading=10,
            alignment=TA_CENTER,
            textColor=MUTED,
            spaceAfter=7,
            splitLongWords=True,
        ),
        "front_title": ParagraphStyle(
            "NewsFrontTitle",
            parent=base["Heading1"],
            fontName=FONT_BOLD,
            fontSize=18,
            leading=22,
            textColor=INK,
            spaceAfter=5,
            splitLongWords=True,
        ),
        "section": ParagraphStyle(
            "NewsSection",
            parent=base["Heading2"],
            fontName=FONT_BOLD,
            fontSize=12.5,
            leading=15,
            textColor=colors.white,
            alignment=TA_CENTER,
            splitLongWords=True,
        ),
        "article_title": ParagraphStyle(
            "NewsArticleTitle",
            parent=base["Heading3"],
            fontName=FONT_BOLD,
            fontSize=12.2,
            leading=15,
            textColor=INK,
            spaceAfter=3,
            splitLongWords=True,
        ),
        "lead": ParagraphStyle(
            "NewsLead",
            parent=base["BodyText"],
            fontName=FONT_BOLD,
            fontSize=9.3,
            leading=12.5,
            textColor=INK,
            spaceAfter=4,
            splitLongWords=True,
        ),
        "body": ParagraphStyle(
            "NewsBody",
            parent=base["BodyText"],
            fontName=FONT_REGULAR,
            fontSize=8.6,
            leading=11.7,
            textColor=INK,
            alignment=TA_LEFT,
            spaceAfter=4,
            splitLongWords=True,
        ),
        "small": ParagraphStyle(
            "NewsSmall",
            parent=base["BodyText"],
            fontName=FONT_REGULAR,
            fontSize=7.1,
            leading=9,
            textColor=MUTED,
            splitLongWords=True,
        ),
        "link": ParagraphStyle(
            "NewsLink",
            parent=base["BodyText"],
            fontName=FONT_REGULAR,
            fontSize=7.1,
            leading=9,
            textColor=LINK,
            splitLongWords=True,
        ),
    }


def section_band(name: str, styles: dict[str, ParagraphStyle]) -> Table:
    table = Table([[Paragraph(name, styles["section"])]], colWidths=[CONTENT_WIDTH])
    table.setStyle(
        TableStyle(
            [
                ("BACKGROUND", (0, 0), (-1, -1), RULE),
                ("BOX", (0, 0), (-1, -1), 0.5, RULE),
                ("TOPPADDING", (0, 0), (-1, -1), 4),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 4),
            ]
        )
    )
    return table


def article_card(article: Article, styles: dict[str, ParagraphStyle], featured: bool = False) -> Table:
    rows = []
    if featured:
        rows.append([Paragraph(markdown_inline(article.section), styles["kicker"])])
    rows.extend(
        [
            [Paragraph(markdown_inline(article.title), styles["front_title" if featured else "article_title"])],
            [Paragraph(markdown_inline(article.lead), styles["lead"])],
        ]
    )
    fact_items = [ListItem(Paragraph(markdown_inline(fact), styles["body"])) for fact in article.facts[:4]]
    if fact_items:
        rows.append([ListFlowable(fact_items, bulletType="bullet", leftIndent=11)])
    if article.analysis:
        rows.append([Paragraph(f"<b>Analiza:</b> {markdown_inline(article.analysis)}", styles["body"])])

    table = Table(rows, colWidths=[CONTENT_WIDTH])
    table.setStyle(
        TableStyle(
            [
                ("BACKGROUND", (0, 0), (-1, -1), PAPER if featured else colors.white),
                ("BOX", (0, 0), (-1, -1), 0.65, GOLD if featured else BORDER),
                ("LEFTPADDING", (0, 0), (-1, -1), 8),
                ("RIGHTPADDING", (0, 0), (-1, -1), 8),
                ("TOPPADDING", (0, 0), (-1, -1), 7),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 7),
            ]
        )
    )
    return table


def draw_page(canvas, doc, title: str) -> None:
    draw_mobile_page(
        canvas,
        doc,
        title=title,
        footer_label=title,
        page_label="strona",
        accent=RULE,
        accent_rule=AMBER,
        paper=PAPER,
        rule=RULE,
    )


def render_newspaper_pdf(markdown_report: Path, pdf_output: Path, topic_name: str | None = None) -> None:
    report_text = read_text(markdown_report)
    title, metadata = split_metadata(report_text)
    articles_by_section = parse_newspaper_articles(report_text)
    styles = build_styles()
    source_items = source_links(report_text)
    first_article = articles_by_section[REQUIRED_SECTIONS[0]][0]

    story = [
        Paragraph("PAVBOT", styles["kicker"]),
        Paragraph("THE MOBILE EDITION", styles["masthead"]),
        Paragraph(
            " | ".join(
                bit
                for bit in [
                    f"Temat: {topic_name}" if topic_name else "",
                    f"Data: {metadata.get('date', markdown_report.stem)}",
                    f"Status: {metadata.get('status', 'brak danych')}",
                    f"Wydanie: {datetime.now().strftime('%Y-%m-%d %H:%M')}",
                ]
                if bit
            ),
            styles["subtitle"],
        ),
        HRFlowable(width="100%", thickness=1.0, color=RULE, spaceAfter=8),
        article_card(first_article, styles, featured=True),
        Spacer(1, 7),
    ]

    for section in REQUIRED_SECTIONS:
        section_articles = articles_by_section[section]
        if section == first_article.section and section_articles and section_articles[0] is first_article:
            section_articles = section_articles[1:]
        if not section_articles:
            continue
        story.append(section_band(section, styles))
        story.append(Spacer(1, 5))
        for article in section_articles[:3]:
            story.append(KeepTogether([article_card(article, styles), Spacer(1, 5)]))
        if section != REQUIRED_SECTIONS[-1]:
            story.append(PageBreak())

    story.append(PageBreak())
    story.append(section_band("Źródła", styles))
    story.append(Spacer(1, 6))
    if source_items:
        unique: list[tuple[str, str]] = []
        seen: set[str] = set()
        for label, url in source_items:
            if url in seen:
                continue
            seen.add(url)
            unique.append((label, url))
        items = []
        for label, url in unique[:30]:
            safe_url = escape(url, quote=True)
            items.append(ListItem(Paragraph(f'<a href="{safe_url}">{escape(label)}</a>', styles["link"])))
        story.append(ListFlowable(items, bulletType="bullet", leftIndent=12))
    else:
        story.append(Paragraph("Brak linków źródłowych w raporcie.", styles["body"]))
    story.append(Spacer(1, 8))
    story.append(
        Paragraph(
            "Wydanie oddziela fakty od analizy. Sekcje bez nowych ustaleń są oznaczone jako brak materialnej zmiany.",
            styles["small"],
        )
    )

    pdf_output.parent.mkdir(parents=True, exist_ok=True)
    doc = SimpleDocTemplate(
        str(pdf_output),
        pagesize=PAGE_SIZE,
        leftMargin=PAGE_MARGIN_X,
        rightMargin=PAGE_MARGIN_X,
        topMargin=PAGE_MARGIN_TOP,
        bottomMargin=PAGE_MARGIN_BOTTOM,
        title=title,
        author="Pavbot",
        subject=f"Mobile newspaper: {topic_name or markdown_report.stem}",
    )
    doc.build(
        story,
        onFirstPage=lambda canvas, doc_obj: draw_page(canvas, doc_obj, title),
        onLaterPages=lambda canvas, doc_obj: draw_page(canvas, doc_obj, title),
    )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("markdown_report", type=Path)
    parser.add_argument("pdf_output", type=Path)
    parser.add_argument("--topic", dest="topic_name")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    render_newspaper_pdf(args.markdown_report, args.pdf_output, topic_name=args.topic_name)
    print(args.pdf_output)


if __name__ == "__main__":
    main()
