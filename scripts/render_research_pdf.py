#!/usr/bin/env python3
"""Render a Pavbot Markdown research report to a polished PDF."""

from __future__ import annotations

import argparse
import html
import re
from pathlib import Path

from reportlab.lib import colors
from reportlab.lib.enums import TA_CENTER, TA_LEFT
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import mm
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import (
    HRFlowable,
    KeepTogether,
    Paragraph,
    SimpleDocTemplate,
    Spacer,
    Table,
    TableStyle,
)


INK = colors.HexColor("#111827")
MUTED = colors.HexColor("#64748B")
ACCENT = colors.HexColor("#0F766E")
ACCENT_DARK = colors.HexColor("#134E4A")
ACCENT_LIGHT = colors.HexColor("#CCFBF1")
SURFACE = colors.HexColor("#F8FAFC")
BORDER = colors.HexColor("#CBD5E1")
LINK = colors.HexColor("#1D4ED8")


def register_fonts() -> tuple[str, str]:
    regular_candidates = [
        "/System/Library/Fonts/Supplemental/Arial Unicode.ttf",
        "/System/Library/Fonts/Supplemental/Arial.ttf",
        "/Library/Fonts/Arial Unicode.ttf",
        "/System/Library/Fonts/Supplemental/DejaVu Sans.ttf",
    ]
    bold_candidates = [
        "/System/Library/Fonts/Supplemental/Arial Bold.ttf",
        "/Library/Fonts/Arial Bold.ttf",
        "/System/Library/Fonts/Supplemental/DejaVu Sans Bold.ttf",
    ]

    regular = next((Path(path) for path in regular_candidates if Path(path).exists()), None)
    bold = next((Path(path) for path in bold_candidates if Path(path).exists()), None)

    if regular:
        pdfmetrics.registerFont(TTFont("PavbotSans", str(regular)))
        if bold:
            pdfmetrics.registerFont(TTFont("PavbotSans-Bold", str(bold)))
            return "PavbotSans", "PavbotSans-Bold"
        return "PavbotSans", "PavbotSans"

    return "Helvetica", "Helvetica-Bold"


FONT_REGULAR, FONT_BOLD = register_fonts()


def markdown_inline(text: str) -> str:
    escaped = html.escape(text)
    escaped = re.sub(r"\*\*(.+?)\*\*", r"<b>\1</b>", escaped)
    escaped = re.sub(r"`([^`]+)`", rf"<font name='{FONT_REGULAR}'>\1</font>", escaped)

    def link_repl(match: re.Match[str]) -> str:
        label = match.group(1)
        url = match.group(2)
        return f'<a href="{url}"><font color="#1D4ED8">{label}</font></a>'

    return re.sub(r"\[([^\]]+)\]\((https?://[^)]+)\)", link_repl, escaped)


def is_table_separator(line: str) -> bool:
    cells = [cell.strip() for cell in line.strip().strip("|").split("|")]
    return bool(cells) and all(re.fullmatch(r":?-{3,}:?", cell or "") for cell in cells)


def collect_table(lines: list[str], start: int) -> tuple[list[list[str]], int]:
    rows: list[list[str]] = []
    i = start
    while i < len(lines) and lines[i].strip().startswith("|"):
        if not is_table_separator(lines[i]):
            rows.append([cell.strip() for cell in lines[i].strip().strip("|").split("|")])
        i += 1
    return rows, i


def read_metadata(lines: list[str]) -> dict[str, str]:
    metadata: dict[str, str] = {}
    for line in lines[:12]:
        if ":" not in line:
            continue
        key, value = line.split(":", 1)
        key = key.strip().lower()
        if key in {"date", "status"}:
            metadata[key] = value.strip()
    return metadata


def build_styles() -> dict[str, ParagraphStyle]:
    base = getSampleStyleSheet()
    return {
        "title": ParagraphStyle(
            "PavbotTitle",
            parent=base["Title"],
            fontName=FONT_BOLD,
            fontSize=23,
            leading=28,
            textColor=INK,
            alignment=TA_CENTER,
            spaceAfter=5,
            splitLongWords=True,
        ),
        "subtitle": ParagraphStyle(
            "PavbotSubtitle",
            parent=base["Normal"],
            fontName=FONT_REGULAR,
            fontSize=9.5,
            leading=13,
            textColor=MUTED,
            alignment=TA_CENTER,
            spaceAfter=10,
            splitLongWords=True,
        ),
        "kicker": ParagraphStyle(
            "PavbotKicker",
            parent=base["Normal"],
            fontName=FONT_BOLD,
            fontSize=8,
            leading=10,
            textColor=ACCENT_DARK,
            alignment=TA_CENTER,
            spaceAfter=8,
        ),
        "h2": ParagraphStyle(
            "PavbotH2",
            parent=base["Heading2"],
            fontName=FONT_BOLD,
            fontSize=14.2,
            leading=18,
            textColor=ACCENT_DARK,
            spaceBefore=12,
            spaceAfter=5,
            splitLongWords=True,
        ),
        "h3": ParagraphStyle(
            "PavbotH3",
            parent=base["Heading3"],
            fontName=FONT_BOLD,
            fontSize=11.4,
            leading=14,
            textColor=INK,
            spaceBefore=8,
            spaceAfter=4,
            splitLongWords=True,
        ),
        "body": ParagraphStyle(
            "PavbotBody",
            parent=base["BodyText"],
            fontName=FONT_REGULAR,
            fontSize=9.2,
            leading=12.8,
            textColor=INK,
            alignment=TA_LEFT,
            spaceAfter=4.5,
            splitLongWords=True,
        ),
        "bullet": ParagraphStyle(
            "PavbotBullet",
            parent=base["BodyText"],
            fontName=FONT_REGULAR,
            fontSize=9,
            leading=12.5,
            textColor=INK,
            leftIndent=6 * mm,
            firstLineIndent=-3 * mm,
            spaceAfter=4,
            splitLongWords=True,
        ),
        "table": ParagraphStyle(
            "PavbotTable",
            parent=base["BodyText"],
            fontName=FONT_REGULAR,
            fontSize=7.15,
            leading=9.0,
            textColor=INK,
            splitLongWords=True,
        ),
        "table_header": ParagraphStyle(
            "PavbotTableHeader",
            parent=base["BodyText"],
            fontName=FONT_BOLD,
            fontSize=7.25,
            leading=9.2,
            textColor=ACCENT_DARK,
            splitLongWords=True,
        ),
    }


def column_widths(column_count: int) -> list[float]:
    usable_width = A4[0] - 32 * mm
    if column_count == 4:
        return [19 * mm, 43 * mm, 75 * mm, usable_width - 137 * mm]
    if column_count == 3:
        return [usable_width * 0.22, usable_width * 0.43, usable_width * 0.35]
    return [usable_width / column_count] * column_count


def make_table(rows: list[list[str]], styles: dict[str, ParagraphStyle]) -> Table:
    max_cols = max(len(row) for row in rows)
    normalized = [row + [""] * (max_cols - len(row)) for row in rows]
    data = []
    for row_index, row in enumerate(normalized):
        style = styles["table_header"] if row_index == 0 else styles["table"]
        data.append([Paragraph(markdown_inline(cell), style) for cell in row])

    table = Table(data, colWidths=column_widths(max_cols), repeatRows=1, hAlign="LEFT")
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
                ("ROWBACKGROUNDS", (0, 1), (-1, -1), [colors.white, SURFACE]),
            ]
        )
    )
    return table


def parse_markdown(markdown_text: str, topic_name: str | None) -> tuple[str, list]:
    styles = build_styles()
    story: list = []
    lines = markdown_text.splitlines()
    metadata = read_metadata(lines)
    title = topic_name or "Pavbot Research Report"
    title_seen = False
    i = 0

    while i < len(lines):
        line = lines[i].rstrip()
        stripped = line.strip()

        if not stripped:
            story.append(Spacer(1, 2.4 * mm))
            i += 1
            continue

        if stripped.startswith("|"):
            rows, i = collect_table(lines, i)
            if rows:
                story.append(make_table(rows, styles))
                story.append(Spacer(1, 4 * mm))
            continue

        if stripped.startswith("# "):
            title = stripped[2:].strip()
            date = metadata.get("date", "")
            status = metadata.get("status", "")
            subtitle_bits = [bit for bit in [f"Topic: {topic_name}" if topic_name else "", f"Date: {date}" if date else "", f"Status: {status}" if status else ""] if bit]
            story.append(Paragraph("PAVBOT RESEARCH BRIEF", styles["kicker"]))
            story.append(Paragraph(markdown_inline(title), styles["title"]))
            story.append(Paragraph(" | ".join(subtitle_bits), styles["subtitle"]))
            story.append(HRFlowable(width="100%", thickness=1.1, color=ACCENT, spaceAfter=7))
            title_seen = True
            i += 1
            continue

        if stripped.startswith("## "):
            story.append(KeepTogether([Paragraph(markdown_inline(stripped[3:].strip()), styles["h2"])]))
            i += 1
            continue

        if stripped.startswith("### "):
            story.append(Paragraph(markdown_inline(stripped[4:].strip()), styles["h3"]))
            i += 1
            continue

        if stripped.startswith("- "):
            story.append(Paragraph("- " + markdown_inline(stripped[2:].strip()), styles["bullet"]))
            i += 1
            continue

        if re.fullmatch(r"[A-Za-z ]+: .+", stripped):
            story.append(Paragraph(markdown_inline(stripped), styles["body"]))
            i += 1
            continue

        if not title_seen:
            story.append(Paragraph("PAVBOT RESEARCH BRIEF", styles["kicker"]))
            story.append(Paragraph(markdown_inline(title), styles["title"]))
            story.append(HRFlowable(width="100%", thickness=1.1, color=ACCENT, spaceAfter=7))
            title_seen = True

        story.append(Paragraph(markdown_inline(stripped), styles["body"]))
        i += 1

    return title, story


def draw_page(canvas, doc, title: str) -> None:
    canvas.saveState()
    width, height = A4
    canvas.setFillColor(ACCENT)
    canvas.rect(0, height - 8 * mm, width, 8 * mm, stroke=0, fill=1)
    canvas.setFillColor(MUTED)
    canvas.setFont(FONT_REGULAR, 7.5)
    canvas.drawString(16 * mm, 10 * mm, title[:95])
    canvas.drawRightString(width - 16 * mm, 10 * mm, f"Page {doc.page}")
    canvas.restoreState()


def render_pdf(markdown_report: Path, pdf_output: Path, topic_name: str | None = None) -> None:
    markdown_text = markdown_report.read_text(encoding="utf-8")
    title, story = parse_markdown(markdown_text, topic_name)
    pdf_output.parent.mkdir(parents=True, exist_ok=True)
    doc = SimpleDocTemplate(
        str(pdf_output),
        pagesize=A4,
        leftMargin=16 * mm,
        rightMargin=16 * mm,
        topMargin=18 * mm,
        bottomMargin=16 * mm,
        title=title,
        author="Pavbot",
        subject=f"Pavbot research report: {topic_name or markdown_report.stem}",
    )
    doc.build(
        story,
        onFirstPage=lambda canvas, doc_obj: draw_page(canvas, doc_obj, title),
        onLaterPages=lambda canvas, doc_obj: draw_page(canvas, doc_obj, title),
    )


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("markdown_report", type=Path)
    parser.add_argument("pdf_output", type=Path)
    parser.add_argument("--topic", dest="topic_name")
    args = parser.parse_args()
    render_pdf(args.markdown_report, args.pdf_output, topic_name=args.topic_name)


if __name__ == "__main__":
    main()
