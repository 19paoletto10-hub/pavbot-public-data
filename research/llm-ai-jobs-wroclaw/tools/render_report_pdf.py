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
    PageBreak,
    Paragraph,
    SimpleDocTemplate,
    Spacer,
    Table,
    TableStyle,
)


ACCENT = colors.HexColor("#155E75")
ACCENT_DARK = colors.HexColor("#0F172A")
MUTED = colors.HexColor("#64748B")
LIGHT_BG = colors.HexColor("#F1F5F9")
GRID = colors.HexColor("#CBD5E1")


def register_fonts() -> tuple[str, str]:
    regular_candidates = [
        "/Users/promaczek/.cache/codex-runtimes/codex-primary-runtime/dependencies/native/libreoffice-headless/libreoffice/LibreOfficeDev.app/Contents/Resources/fonts/truetype/NotoSans-Regular.ttf",
        "/Users/promaczek/.cache/codex-runtimes/codex-primary-runtime/dependencies/native/libreoffice-headless/libreoffice/LibreOfficeDev.app/Contents/Resources/fonts/truetype/DejaVuSans.ttf",
        "/System/Library/Fonts/Supplemental/Tahoma.ttf",
        "/System/Library/Fonts/Supplemental/Verdana.ttf",
        "/System/Library/Fonts/Supplemental/Arial Unicode.ttf",
        "/System/Library/Fonts/Supplemental/Arial.ttf",
        "/Library/Fonts/Arial Unicode.ttf",
    ]
    bold_candidates = [
        "/Users/promaczek/.cache/codex-runtimes/codex-primary-runtime/dependencies/native/libreoffice-headless/libreoffice/LibreOfficeDev.app/Contents/Resources/fonts/truetype/NotoSans-Bold.ttf",
        "/Users/promaczek/.cache/codex-runtimes/codex-primary-runtime/dependencies/native/libreoffice-headless/libreoffice/LibreOfficeDev.app/Contents/Resources/fonts/truetype/DejaVuSans-Bold.ttf",
        "/System/Library/Fonts/Supplemental/Tahoma Bold.ttf",
        "/System/Library/Fonts/Supplemental/Verdana Bold.ttf",
        "/System/Library/Fonts/Supplemental/Arial Bold.ttf",
        "/Library/Fonts/Arial Bold.ttf",
    ]

    regular = next((Path(p) for p in regular_candidates if Path(p).exists()), None)
    bold = next((Path(p) for p in bold_candidates if Path(p).exists()), None)

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
    escaped = re.sub(r"`([^`]+)`", r"<font name='%s'>\1</font>" % FONT_REGULAR, escaped)

    def link_repl(match: re.Match[str]) -> str:
        label = match.group(1)
        url = match.group(2)
        return (
            f"<a href=\"{url}\"><font color=\"#0B5CAD\">{label}</font></a>"
            f" <font color=\"#64748B\">({url})</font>"
        )

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


def build_styles() -> dict[str, ParagraphStyle]:
    base = getSampleStyleSheet()
    return {
        "title": ParagraphStyle(
            "Title",
            parent=base["Title"],
            fontName=FONT_BOLD,
            fontSize=24,
            leading=30,
            textColor=ACCENT_DARK,
            alignment=TA_CENTER,
            spaceAfter=8,
        ),
        "subtitle": ParagraphStyle(
            "Subtitle",
            parent=base["Normal"],
            fontName=FONT_REGULAR,
            fontSize=10,
            leading=14,
            textColor=MUTED,
            alignment=TA_CENTER,
            spaceAfter=14,
        ),
        "h2": ParagraphStyle(
            "Heading2",
            parent=base["Heading2"],
            fontName=FONT_BOLD,
            fontSize=15,
            leading=19,
            textColor=ACCENT,
            spaceBefore=13,
            spaceAfter=6,
        ),
        "h3": ParagraphStyle(
            "Heading3",
            parent=base["Heading3"],
            fontName=FONT_BOLD,
            fontSize=12,
            leading=15,
            textColor=ACCENT_DARK,
            spaceBefore=9,
            spaceAfter=4,
        ),
        "body": ParagraphStyle(
            "Body",
            parent=base["BodyText"],
            fontName=FONT_REGULAR,
            fontSize=9.4,
            leading=13.2,
            textColor=ACCENT_DARK,
            alignment=TA_LEFT,
            spaceAfter=5,
        ),
        "bullet": ParagraphStyle(
            "Bullet",
            parent=base["BodyText"],
            fontName=FONT_REGULAR,
            fontSize=9.2,
            leading=12.8,
            textColor=ACCENT_DARK,
            leftIndent=6 * mm,
            firstLineIndent=-3 * mm,
            spaceAfter=4,
        ),
        "small": ParagraphStyle(
            "Small",
            parent=base["BodyText"],
            fontName=FONT_REGULAR,
            fontSize=7.4,
            leading=9.6,
            textColor=ACCENT_DARK,
        ),
    }


def make_table(rows: list[list[str]], styles: dict[str, ParagraphStyle]) -> Table:
    max_cols = max(len(row) for row in rows)
    normalized = [row + [""] * (max_cols - len(row)) for row in rows]
    data = [
        [Paragraph(markdown_inline(cell), styles["small"]) for cell in row]
        for row in normalized
    ]
    usable_width = A4[0] - 34 * mm
    col_widths = [usable_width / max_cols] * max_cols
    table = Table(data, colWidths=col_widths, repeatRows=1, hAlign="LEFT")
    table.setStyle(
        TableStyle(
            [
                ("BACKGROUND", (0, 0), (-1, 0), LIGHT_BG),
                ("TEXTCOLOR", (0, 0), (-1, 0), ACCENT_DARK),
                ("FONTNAME", (0, 0), (-1, 0), FONT_BOLD),
                ("GRID", (0, 0), (-1, -1), 0.35, GRID),
                ("VALIGN", (0, 0), (-1, -1), "TOP"),
                ("LEFTPADDING", (0, 0), (-1, -1), 4),
                ("RIGHTPADDING", (0, 0), (-1, -1), 4),
                ("TOPPADDING", (0, 0), (-1, -1), 4),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 4),
            ]
        )
    )
    return table


def parse_markdown(markdown_text: str) -> tuple[str, list]:
    styles = build_styles()
    story: list = []
    lines = markdown_text.splitlines()
    title = "LLM/AI Jobs Wrocław"
    i = 0
    title_seen = False

    while i < len(lines):
        line = lines[i].rstrip()
        stripped = line.strip()

        if not stripped:
            story.append(Spacer(1, 3 * mm))
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
            if title_seen:
                story.append(PageBreak())
            story.append(Paragraph(markdown_inline(title), styles["title"]))
            story.append(Paragraph("Pavbot research automation", styles["subtitle"]))
            story.append(HRFlowable(width="100%", thickness=1.1, color=ACCENT, spaceAfter=7))
            title_seen = True
            i += 1
            continue

        if stripped.startswith("## "):
            story.append(Paragraph(markdown_inline(stripped[3:].strip()), styles["h2"]))
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
    canvas.drawString(17 * mm, 10 * mm, title[:95])
    canvas.drawRightString(width - 17 * mm, 10 * mm, f"Page {doc.page}")
    canvas.restoreState()


def render_pdf(markdown_path: Path, pdf_path: Path) -> None:
    text = markdown_path.read_text(encoding="utf-8")
    title, story = parse_markdown(text)
    pdf_path.parent.mkdir(parents=True, exist_ok=True)
    doc = SimpleDocTemplate(
        str(pdf_path),
        pagesize=A4,
        leftMargin=17 * mm,
        rightMargin=17 * mm,
        topMargin=18 * mm,
        bottomMargin=17 * mm,
        title=title,
        author="Pavbot",
        subject="LLM/AI jobs research",
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
    args = parser.parse_args()
    render_pdf(args.markdown_report, args.pdf_output)


if __name__ == "__main__":
    main()
