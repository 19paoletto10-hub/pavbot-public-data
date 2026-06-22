#!/usr/bin/env python3
"""Create a polished PDF brief for a Pavbot podcast package."""

from __future__ import annotations

import json
import re
import sys
from datetime import datetime
from html import escape
from pathlib import Path

from reportlab.lib import colors
from reportlab.lib.enums import TA_LEFT
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import cm
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import (
    Frame,
    KeepTogether,
    ListFlowable,
    ListItem,
    PageTemplate,
    Paragraph,
    SimpleDocTemplate,
    Spacer,
    Table,
    TableStyle,
)


NAVY = colors.HexColor("#17233C")
BLUE = colors.HexColor("#2563EB")
LIGHT_BLUE = colors.HexColor("#EFF6FF")
GRAY = colors.HexColor("#5B6577")
LIGHT_GRAY = colors.HexColor("#F6F8FB")
BORDER = colors.HexColor("#D9E1EF")


def fail(message: str, code: int = 1) -> None:
    print(message, file=sys.stderr)
    raise SystemExit(code)


def register_fonts() -> tuple[str, str]:
    regular_candidates = [
        "/System/Library/Fonts/Supplemental/Arial Unicode.ttf",
        "/System/Library/Fonts/Supplemental/Arial.ttf",
        "/Library/Fonts/Arial.ttf",
    ]
    bold_candidates = [
        "/System/Library/Fonts/Supplemental/Arial Bold.ttf",
        "/Library/Fonts/Arial Bold.ttf",
    ]

    regular = next((Path(p) for p in regular_candidates if Path(p).is_file()), None)
    bold = next((Path(p) for p in bold_candidates if Path(p).is_file()), None)
    if regular:
        pdfmetrics.registerFont(TTFont("PavbotRegular", str(regular)))
    else:
        return "Helvetica", "Helvetica-Bold"
    if bold:
        pdfmetrics.registerFont(TTFont("PavbotBold", str(bold)))
        return "PavbotRegular", "PavbotBold"
    return "PavbotRegular", "Helvetica-Bold"


def read_text(path: Path) -> str:
    if not path.is_file():
        fail(f"missing file: {path}")
    return path.read_text(encoding="utf-8")


def paragraphs_from_markdown(text: str) -> list[str]:
    paragraphs: list[str] = []
    current: list[str] = []
    for raw in text.splitlines():
        line = raw.strip()
        if not line:
            if current:
                paragraphs.append(" ".join(current))
                current = []
            continue
        if line.startswith("#"):
            continue
        current.append(line)
    if current:
        paragraphs.append(" ".join(current))
    return paragraphs


def source_links(text: str) -> list[tuple[str, str]]:
    links: list[tuple[str, str]] = []
    for label, url in re.findall(r"\[([^\]]+)\]\((https?://[^)]+)\)", text):
        links.append((label.strip(), url.strip()))
    return links


def section_links(text: str, heading: str) -> list[tuple[str, str]]:
    lines = text.splitlines()
    selected: list[str] = []
    in_section = False
    for line in lines:
        if line.startswith("## "):
            if in_section:
                break
            in_section = line.strip() == heading
            continue
        if in_section:
            selected.append(line)
    return source_links("\n".join(selected))


def short(text: str, limit: int = 360) -> str:
    text = re.sub(r"\s+", " ", text).strip()
    if len(text) <= limit:
        return text
    window = text[:limit].rstrip()
    sentence_end = max(window.rfind("."), window.rfind("?"), window.rfind("!"))
    if sentence_end >= min(80, int(limit * 0.3)):
        return window[: sentence_end + 1]
    cut = window.rsplit(" ", 1)[0].rstrip(" ,;:-")
    return cut + "..."


def split_lead_sentence(text: str) -> tuple[str, str]:
    text = re.sub(r"\s+", " ", text).strip()
    match = re.match(r"(.+?[.!?])\s+(.*)", text)
    if not match:
        return text, text
    return match.group(1).strip(), match.group(2).strip()


def mmss(seconds: float | int | str) -> str:
    try:
        total = int(round(float(seconds)))
    except Exception:
        return "brak danych"
    return f"{total // 60}:{total % 60:02d}"


def build_styles(font: str, bold_font: str):
    styles = getSampleStyleSheet()
    styles.add(
        ParagraphStyle(
            name="TitlePavbot",
            fontName=bold_font,
            fontSize=24,
            leading=29,
            textColor=NAVY,
            spaceAfter=10,
        )
    )
    styles.add(
        ParagraphStyle(
            name="SubtitlePavbot",
            fontName=font,
            fontSize=10.5,
            leading=15,
            textColor=GRAY,
            spaceAfter=14,
        )
    )
    styles.add(
        ParagraphStyle(
            name="SectionPavbot",
            fontName=bold_font,
            fontSize=14,
            leading=18,
            textColor=NAVY,
            spaceBefore=12,
            spaceAfter=8,
        )
    )
    styles.add(
        ParagraphStyle(
            name="BodyPavbot",
            fontName=font,
            fontSize=9.7,
            leading=14,
            textColor=colors.HexColor("#202938"),
            alignment=TA_LEFT,
            spaceAfter=7,
        )
    )
    styles.add(
        ParagraphStyle(
            name="SmallPavbot",
            fontName=font,
            fontSize=8.5,
            leading=12,
            textColor=GRAY,
        )
    )
    styles.add(
        ParagraphStyle(
            name="CardTitlePavbot",
            fontName=bold_font,
            fontSize=10.5,
            leading=13,
            textColor=NAVY,
            spaceAfter=4,
        )
    )
    styles.add(
        ParagraphStyle(
            name="LinkPavbot",
            fontName=font,
            fontSize=8.4,
            leading=11.5,
            textColor=BLUE,
        )
    )
    return styles


def make_card(title: str, body: str, styles):
    return Table(
        [[Paragraph(escape(title), styles["CardTitlePavbot"])], [Paragraph(escape(body), styles["BodyPavbot"])]],
        colWidths=[16.2 * cm],
        style=TableStyle(
            [
                ("BACKGROUND", (0, 0), (-1, -1), LIGHT_GRAY),
                ("BOX", (0, 0), (-1, -1), 0.7, BORDER),
                ("LEFTPADDING", (0, 0), (-1, -1), 10),
                ("RIGHTPADDING", (0, 0), (-1, -1), 10),
                ("TOPPADDING", (0, 0), (-1, -1), 8),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 8),
            ]
        ),
        hAlign="LEFT",
    )


def footer(canvas, doc):
    canvas.saveState()
    canvas.setStrokeColor(BORDER)
    canvas.setLineWidth(0.5)
    canvas.line(doc.leftMargin, 1.55 * cm, A4[0] - doc.rightMargin, 1.55 * cm)
    canvas.setFont("Helvetica", 8)
    canvas.setFillColor(GRAY)
    canvas.drawString(doc.leftMargin, 1.1 * cm, "Pavbot research brief")
    canvas.drawRightString(A4[0] - doc.rightMargin, 1.1 * cm, f"Strona {doc.page}")
    canvas.restoreState()


def main() -> None:
    if len(sys.argv) not in (2, 3):
        fail("usage: render-podcast-brief-pdf.py PODCAST_DIR [OUTPUT_PDF]", 64)

    podcast_dir = Path(sys.argv[1])
    output_pdf = Path(sys.argv[2]) if len(sys.argv) == 3 else podcast_dir / "brief.pdf"
    script = read_text(podcast_dir / "script.md")
    sources = read_text(podcast_dir / "sources.md")
    render_data = {}
    render_json = podcast_dir / "render.json"
    if render_json.is_file():
        render_data = json.loads(render_json.read_text(encoding="utf-8"))

    font, bold_font = register_fonts()
    styles = build_styles(font, bold_font)
    paragraphs = paragraphs_from_markdown(script)
    source_used = section_links(sources, "## Źródła użyte w scenariuszu") or source_links(sources)
    checked_unused = section_links(sources, "## Źródła sprawdzone, ale niewykorzystane")
    unavailable = section_links(sources, "## Źródła niedostępne lub niejednoznaczne")

    date_label = podcast_dir.name
    topic_label = podcast_dir.parent.parent.name
    created_label = datetime.now().strftime("%Y-%m-%d %H:%M")

    output_pdf.parent.mkdir(parents=True, exist_ok=True)
    doc = SimpleDocTemplate(
        str(output_pdf),
        pagesize=A4,
        leftMargin=2.0 * cm,
        rightMargin=2.0 * cm,
        topMargin=1.7 * cm,
        bottomMargin=2.0 * cm,
        title=f"Pavbot {topic_label} brief {date_label}",
        author="Pavbot",
    )
    frame = Frame(doc.leftMargin, doc.bottomMargin, doc.width, doc.height, id="normal")
    doc.addPageTemplates([PageTemplate(id="pavbot", frames=[frame], onPage=footer)])

    story = []
    story.append(Paragraph(f"Pavbot Research Brief - {escape(date_label)}", styles["TitlePavbot"]))
    story.append(
        Paragraph(
            f"Temat: <b>{escape(topic_label)}</b> | Wygenerowano: {escape(created_label)} | "
            f"Audio: {escape(str(render_data.get('engine_used', 'brak')))} / "
            f"{escape(str(render_data.get('model', 'brak')))}",
            styles["SubtitlePavbot"],
        )
    )

    meta_table = Table(
        [
            ["Długość audio", mmss(render_data.get("duration_seconds", ""))],
            ["Liczba słów", str(render_data.get("word_count", "brak danych"))],
            ["Backend TTS", str(render_data.get("engine_used", "brak danych"))],
            ["Model", str(render_data.get("model", "brak danych"))],
        ],
        colWidths=[4.5 * cm, 11.5 * cm],
        style=TableStyle(
            [
                ("BACKGROUND", (0, 0), (-1, -1), LIGHT_BLUE),
                ("BOX", (0, 0), (-1, -1), 0.7, BORDER),
                ("INNERGRID", (0, 0), (-1, -1), 0.35, BORDER),
                ("FONTNAME", (0, 0), (0, -1), bold_font),
                ("FONTNAME", (1, 0), (1, -1), font),
                ("TEXTCOLOR", (0, 0), (-1, -1), NAVY),
                ("FONTSIZE", (0, 0), (-1, -1), 9),
                ("LEFTPADDING", (0, 0), (-1, -1), 8),
                ("RIGHTPADDING", (0, 0), (-1, -1), 8),
                ("TOPPADDING", (0, 0), (-1, -1), 7),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 7),
            ]
        ),
    )
    story.append(meta_table)
    story.append(Spacer(1, 0.35 * cm))

    story.append(Paragraph("Najważniejsze informacje", styles["SectionPavbot"]))
    cards = []
    for para in paragraphs[1:6]:
        title, body = split_lead_sentence(para)
        cards.append(make_card(title, short(body or para, 310), styles))
    for card in cards[:5]:
        story.append(KeepTogether([card, Spacer(1, 0.18 * cm)]))

    story.append(Paragraph("Kontekst redakcyjny", styles["SectionPavbot"]))
    for para in paragraphs[:3]:
        story.append(Paragraph(escape(short(para, 520)), styles["BodyPavbot"]))

    story.append(Paragraph("Źródła użyte", styles["SectionPavbot"]))
    items = []
    for label, url in source_used[:14]:
        safe_label = escape(label)
        safe_url = escape(url, quote=True)
        items.append(ListItem(Paragraph(f'<a href="{safe_url}">{safe_label}</a>', styles["LinkPavbot"])))
    if items:
        story.append(ListFlowable(items, bulletType="bullet", leftIndent=14))
    else:
        story.append(Paragraph("Brak linków źródłowych w sources.md.", styles["BodyPavbot"]))

    if checked_unused or unavailable:
        story.append(Paragraph("Uwagi źródłowe", styles["SectionPavbot"]))
        notes = []
        for label, url in checked_unused[:5]:
            notes.append(f"Sprawdzone, niewykorzystane: {label} ({url})")
        for label, url in unavailable[:5]:
            notes.append(f"Niedostępne lub niejednoznaczne: {label} ({url})")
        if not notes and "Reddit" in sources:
            notes.append("Reddit: publiczny fetch nie dostarczył potwierdzonego materiału do scenariusza.")
        for note in notes[:8]:
            story.append(Paragraph(escape(note), styles["SmallPavbot"]))

    story.append(Spacer(1, 0.3 * cm))
    story.append(
        Paragraph(
            "Dokument wygenerowany lokalnie z plików podcastu. Fakty należy czytać razem z linkami źródłowymi.",
            styles["SmallPavbot"],
        )
    )

    doc.build(story)
    print(output_pdf)


if __name__ == "__main__":
    main()
