#!/usr/bin/env python3
"""Render a mobile-first PDF brief for the current-events topic."""

from __future__ import annotations

import argparse
import json
import re
import sys
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
    ACCENT,
    ACCENT_DARK,
    ACCENT_LIGHT,
    AMBER,
    BORDER,
    CONTENT_WIDTH,
    FONT_BOLD as THEME_FONT_BOLD,
    FONT_REGULAR as THEME_FONT_REGULAR,
    LINK,
    MOBILE_PAGE_SIZE,
    PAGE_MARGIN_BOTTOM,
    PAGE_MARGIN_TOP,
    PAGE_MARGIN_X,
    PAPER,
    SURFACE,
    build_mobile_styles,
    draw_mobile_page,
    source_list_flowable,
)


PAGE_SIZE = MOBILE_PAGE_SIZE
INK = colors.HexColor("#111827")
MUTED = colors.HexColor("#64748B")
WARNING = colors.HexColor("#FEF3C7")


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
        pdfmetrics.registerFont(TTFont("PavbotMobile", str(regular)))
        if bold:
            pdfmetrics.registerFont(TTFont("PavbotMobile-Bold", str(bold)))
            return "PavbotMobile", "PavbotMobile-Bold"
        return "PavbotMobile", "PavbotMobile"
    return "Helvetica", "Helvetica-Bold"


FONT_REGULAR, FONT_BOLD = THEME_FONT_REGULAR, THEME_FONT_BOLD


def markdown_inline(text: str) -> str:
    escaped = escape(text)
    escaped = re.sub(r"\*\*(.+?)\*\*", r"<b>\1</b>", escaped)

    def link_repl(match: re.Match[str]) -> str:
        label = match.group(1)
        url = match.group(2)
        return f'<a href="{escape(url, quote=True)}"><font color="#1D4ED8">{label}</font></a>'

    return re.sub(r"\[([^\]]+)\]\((https?://[^)]+)\)", link_repl, escaped)


def source_links(text: str) -> list[tuple[str, str]]:
    return [(label.strip(), url.strip()) for label, url in re.findall(r"\[([^\]]+)\]\((https?://[^)]+)\)", text)]


def unique_links(links: list[tuple[str, str]]) -> list[tuple[str, str]]:
    unique: list[tuple[str, str]] = []
    seen: set[str] = set()
    for label, url in links:
        if url in seen:
            continue
        seen.add(url)
        unique.append((label, url))
    return unique


def read_text(path: Path) -> str:
    if not path.is_file():
        fail(f"missing file: {path}", 66)
    return path.read_text(encoding="utf-8")


def read_json(path: Path) -> dict:
    if not path.is_file():
        return {}
    return json.loads(path.read_text(encoding="utf-8"))


def split_sections(markdown_text: str) -> tuple[str, dict[str, list[str]], dict[str, str]]:
    title = "Mobile News Brief"
    metadata: dict[str, str] = {}
    sections: dict[str, list[str]] = {}
    current = "Wstęp"

    for raw in markdown_text.splitlines():
        line = raw.rstrip()
        stripped = line.strip()
        if not stripped:
            continue
        if stripped.startswith("# "):
            title = stripped[2:].strip()
            continue
        if stripped.startswith("## "):
            current = stripped[3:].strip()
            sections.setdefault(current, [])
            continue
        if ":" in stripped and not stripped.startswith("- ") and current == "Wstęp":
            key, value = stripped.split(":", 1)
            if key.lower() in {"date", "status"}:
                metadata[key.lower()] = value.strip()
                continue
        section_lines = sections.setdefault(current, [])
        if stripped.startswith("- "):
            section_lines.append(stripped)
        elif section_lines and section_lines[-1].startswith("- "):
            section_lines[-1] = f"{section_lines[-1]} {stripped}"
        else:
            section_lines.append(stripped)

    return title, sections, metadata


def short(text: str, limit: int = 420) -> str:
    text = re.sub(r"\s+", " ", text).strip()
    if len(text) <= limit:
        return text
    cut = text[:limit].rsplit(" ", 1)[0].rstrip(" ,;:")
    return f"{cut}..."


def build_styles() -> dict[str, ParagraphStyle]:
    styles = build_mobile_styles(accent=ACCENT, accent_dark=ACCENT_DARK, body_size=10.05)
    styles["section"] = styles["h2"]
    return styles


def make_card(text: str, styles: dict[str, ParagraphStyle], background=colors.white) -> Table:
    clean = text[2:].strip() if text.startswith("- ") else text
    main_text, source_sep, source_text = clean.partition(" Source: ")
    lead, sentence_sep, rest = main_text.partition(". ")

    if sentence_sep and len(lead) <= 145:
        title = lead
        body = rest
    elif len(main_text) > 145:
        title = main_text[:135].rsplit(" ", 1)[0].rstrip(" ,;:")
        body = main_text[len(title) :].lstrip(" ,;:")
    else:
        title = main_text
        body = rest

    if source_sep:
        source_line = f"Source: {source_text}"
        body = f"{body} {source_line}".strip() if body else source_line

    data = [[Paragraph(markdown_inline(short(title, 145)), styles["card_title"])]]
    if body:
        data.append([Paragraph(markdown_inline(short(body, 420)), styles["body"])])
    table = Table(data, colWidths=[CONTENT_WIDTH])
    table.setStyle(
        TableStyle(
            [
                ("BACKGROUND", (0, 0), (-1, -1), background),
                ("BOX", (0, 0), (-1, -1), 0.55, BORDER),
                ("LINEBEFORE", (0, 0), (0, -1), 2.0, ACCENT),
                ("LEFTPADDING", (0, 0), (-1, -1), 9),
                ("RIGHTPADDING", (0, 0), (-1, -1), 9),
                ("TOPPADDING", (0, 0), (-1, -1), 8),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 8),
            ]
        )
    )
    return table


def variant_rows(tts_data: dict) -> list[list[str]]:
    rows = [["Wariant", "Silnik", "Głos", "Status"]]
    for variant in tts_data.get("variants", []):
        rows.append(
            [
                str(variant.get("id", "brak")),
                str(variant.get("engine", "brak")),
                str(variant.get("voice", variant.get("speaker", "brak"))),
                str(variant.get("status", "planned")),
            ]
        )
    return rows


def make_tts_table(tts_data: dict, styles: dict[str, ParagraphStyle]) -> Table:
    rows = variant_rows(tts_data)
    data = []
    for row_index, row in enumerate(rows):
        style = styles["card_title"] if row_index == 0 else styles["small"]
        data.append([Paragraph(escape(cell), style) for cell in row])
    table = Table(data, colWidths=[82, 70, 118, 80], repeatRows=1)
    table.setStyle(
        TableStyle(
            [
                ("BACKGROUND", (0, 0), (-1, 0), ACCENT_LIGHT),
                ("GRID", (0, 0), (-1, -1), 0.35, BORDER),
                ("VALIGN", (0, 0), (-1, -1), "TOP"),
                ("LEFTPADDING", (0, 0), (-1, -1), 4),
                ("RIGHTPADDING", (0, 0), (-1, -1), 4),
                ("TOPPADDING", (0, 0), (-1, -1), 4),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 4),
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
        page_label="Strona",
        accent=ACCENT_DARK,
        accent_rule=AMBER,
        paper=PAPER,
        rule=BORDER,
    )


def render_mobile_pdf(
    markdown_report: Path,
    podcast_dir: Path,
    pdf_output: Path,
    topic_name: str | None = None,
) -> None:
    report_text = read_text(markdown_report)
    script_text = read_text(podcast_dir / "script.md")
    sources_text = read_text(podcast_dir / "sources.md")
    tts_data = read_json(podcast_dir / "tts_variants.json")
    title, sections, metadata = split_sections(report_text)
    styles = build_styles()
    source_items = unique_links(source_links(report_text) or source_links(sources_text))
    language = str(tts_data.get("language", "pl"))
    speed = str(tts_data.get("speed", "1.1"))

    story = [
        Paragraph("PAVBOT MOBILE NEWS", styles["kicker"]),
        Paragraph(markdown_inline(title), styles["title"]),
        Paragraph(
            " | ".join(
                bit
                for bit in [
                    f"Temat: {topic_name}" if topic_name else "",
                    f"Data: {metadata.get('date', markdown_report.stem)}",
                    f"Status: {metadata.get('status', 'brak danych')}",
                    f"Wygenerowano: {datetime.now().strftime('%Y-%m-%d %H:%M')}",
                ]
                if bit
            ),
            styles["subtitle"],
        ),
        HRFlowable(width="100%", thickness=0.8, color=ACCENT, spaceAfter=6),
        Paragraph(f"Język TTS: {escape(language)} | Prędkość: {escape(speed)}x", styles["body"]),
    ]

    for section_name in ("Nowe fakty", "New Facts"):
        if section_name in sections:
            story.append(Paragraph("Nowe fakty", styles["section"]))
            for line in sections[section_name][:8]:
                story.append(KeepTogether([make_card(line, styles), Spacer(1, 4)]))
            break

    for section_name in ("Interpretacja", "Interpretation"):
        if section_name in sections:
            story.append(Paragraph("Interpretacja", styles["section"]))
            for line in sections[section_name][:5]:
                story.append(KeepTogether([make_card(line, styles, background=SURFACE), Spacer(1, 4)]))
            break

    story.append(Paragraph("Podcast i TTS", styles["section"]))
    story.append(make_tts_table(tts_data, styles))
    story.append(Spacer(1, 5))
    script_preview = re.sub(r"\s+", " ", re.sub(r"^#.*$", "", script_text, flags=re.MULTILINE)).strip()
    if script_preview:
        story.append(Paragraph(markdown_inline(short(script_preview, 520)), styles["body"]))

    story.append(PageBreak())
    story.append(Paragraph("Źródła", styles["section"]))
    if source_items:
        story.append(source_list_flowable(source_items[:24], styles, limit=24))
    else:
        story.append(Paragraph("Brak linków źródłowych w raporcie lub sources.md.", styles["body"]))

    story.append(Spacer(1, 8))
    story.append(
        Paragraph(
            "Fakty i interpretacje należy czytać razem ze źródłami. Humor w scenariuszu jest dodatkiem, nie źródłem wiedzy.",
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
        subject=f"Mobile news brief: {topic_name or markdown_report.stem}",
    )
    doc.build(
        story,
        onFirstPage=lambda canvas, doc_obj: draw_page(canvas, doc_obj, title),
        onLaterPages=lambda canvas, doc_obj: draw_page(canvas, doc_obj, title),
    )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("markdown_report", type=Path)
    parser.add_argument("podcast_dir", type=Path)
    parser.add_argument("pdf_output", type=Path)
    parser.add_argument("--topic", dest="topic_name")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    render_mobile_pdf(
        args.markdown_report,
        args.podcast_dir,
        args.pdf_output,
        topic_name=args.topic_name,
    )
    print(args.pdf_output)


if __name__ == "__main__":
    main()
