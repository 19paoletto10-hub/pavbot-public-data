from __future__ import annotations

import re
from html import escape
from pathlib import Path
from typing import Any

from reportlab.lib import colors
from reportlab.lib.enums import TA_CENTER, TA_LEFT
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import Paragraph, Table, TableStyle


MOBILE_PAGE_SIZE = (390, 844)
PAGE_MARGIN_X = 18
PAGE_MARGIN_TOP = 42
PAGE_MARGIN_BOTTOM = 34
CONTENT_WIDTH = MOBILE_PAGE_SIZE[0] - (2 * PAGE_MARGIN_X)

INK = colors.HexColor("#111827")
MUTED = colors.HexColor("#475569")
ACCENT = colors.HexColor("#2563EB")
ACCENT_DARK = colors.HexColor("#1E3A8A")
ACCENT_LIGHT = colors.HexColor("#DBEAFE")
AMBER = colors.HexColor("#D97706")
BORDER = colors.HexColor("#CBD5E1")
LINK = colors.HexColor("#1D4ED8")
PAPER = colors.HexColor("#F8FAFC")
PAPER_WARM = colors.HexColor("#FFF7ED")
SURFACE = colors.HexColor("#FFFFFF")


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
    if not regular:
        return "Helvetica", "Helvetica-Bold"

    pdfmetrics.registerFont(TTFont("PavbotBody", str(regular)))
    if bold:
        pdfmetrics.registerFont(TTFont("PavbotBody-Bold", str(bold)))
        return "PavbotBody", "PavbotBody-Bold"
    return "PavbotBody", "PavbotBody"


FONT_REGULAR, FONT_BOLD = register_fonts()


def markdown_inline(text: Any) -> str:
    value = escape(re.sub(r"\s+", " ", str(text or "")).strip())
    value = re.sub(r"\*\*(.+?)\*\*", r"<b>\1</b>", value)
    value = re.sub(r"`([^`]+)`", r"<font face=\"Courier\">\1</font>", value)

    def link_repl(match: re.Match[str]) -> str:
        label = escape(match.group(1))
        url = escape(match.group(2), quote=True)
        return f'<a href="{url}"><font color="#1D4ED8">{label}</font></a>'

    return re.sub(r"\[([^\]]+)\]\((https?://[^)]+)\)", link_repl, value)


def build_mobile_styles(
    *,
    accent: colors.Color = ACCENT,
    accent_dark: colors.Color = ACCENT_DARK,
    body_size: float = 10.5,
) -> dict[str, ParagraphStyle]:
    base = getSampleStyleSheet()
    return {
        "kicker": ParagraphStyle(
            "PavbotKicker",
            parent=base["Normal"],
            fontName=FONT_BOLD,
            fontSize=7.8,
            leading=9.5,
            alignment=TA_CENTER,
            textColor=accent_dark,
            spaceAfter=3,
            splitLongWords=True,
        ),
        "title": ParagraphStyle(
            "PavbotTitle",
            parent=base["Title"],
            fontName=FONT_BOLD,
            fontSize=22,
            leading=26,
            alignment=TA_CENTER,
            textColor=INK,
            spaceAfter=4,
            splitLongWords=True,
        ),
        "subtitle": ParagraphStyle(
            "PavbotSubtitle",
            parent=base["Normal"],
            fontName=FONT_REGULAR,
            fontSize=7.7,
            leading=9.5,
            alignment=TA_CENTER,
            textColor=MUTED,
            spaceAfter=6,
            splitLongWords=True,
        ),
        "h2": ParagraphStyle(
            "PavbotH2",
            parent=base["Heading2"],
            fontName=FONT_BOLD,
            fontSize=13.5,
            leading=16,
            textColor=accent_dark,
            spaceBefore=7,
            spaceAfter=5,
            splitLongWords=True,
        ),
        "h3": ParagraphStyle(
            "PavbotH3",
            parent=base["Heading3"],
            fontName=FONT_BOLD,
            fontSize=11.6,
            leading=14,
            textColor=INK,
            spaceBefore=4,
            spaceAfter=3,
            splitLongWords=True,
        ),
        "card_title": ParagraphStyle(
            "PavbotCardTitle",
            parent=base["BodyText"],
            fontName=FONT_BOLD,
            fontSize=10.1,
            leading=12.6,
            textColor=INK,
            spaceAfter=3,
            splitLongWords=True,
        ),
        "body": ParagraphStyle(
            "PavbotBody",
            parent=base["BodyText"],
            fontName=FONT_REGULAR,
            fontSize=body_size,
            leading=body_size + 3,
            alignment=TA_LEFT,
            textColor=INK,
            spaceAfter=4,
            splitLongWords=True,
        ),
        "bullet": ParagraphStyle(
            "PavbotBullet",
            parent=base["BodyText"],
            fontName=FONT_REGULAR,
            fontSize=body_size,
            leading=body_size + 3,
            textColor=INK,
            leftIndent=6,
            firstLineIndent=-6,
            spaceAfter=4,
            splitLongWords=True,
        ),
        "small": ParagraphStyle(
            "PavbotSmall",
            parent=base["BodyText"],
            fontName=FONT_REGULAR,
            fontSize=7.2,
            leading=9,
            textColor=MUTED,
            splitLongWords=True,
        ),
        "link": ParagraphStyle(
            "PavbotLink",
            parent=base["BodyText"],
            fontName=FONT_REGULAR,
            fontSize=8,
            leading=10,
            textColor=LINK,
            splitLongWords=True,
        ),
    }


def key_value_card(
    headers: list[str],
    row: list[str],
    styles: dict[str, ParagraphStyle],
    *,
    background=SURFACE,
    accent=ACCENT,
) -> Table:
    rows = []
    for header, value in zip(headers, row):
        if not str(value).strip():
            continue
        rows.append([Paragraph(f"<b>{markdown_inline(header)}</b>: {markdown_inline(value)}", styles["body"])])
    if not rows:
        rows.append([Paragraph("Brak danych", styles["body"])])
    table = Table(rows, colWidths=[CONTENT_WIDTH])
    table.setStyle(card_style(background=background, border=BORDER, accent=accent))
    return table


def text_card(
    label: str,
    body: str,
    styles: dict[str, ParagraphStyle],
    *,
    background=SURFACE,
    border=BORDER,
    accent=ACCENT,
) -> Table:
    table = Table(
        [
            [Paragraph(markdown_inline(label), styles["card_title"])],
            [Paragraph(markdown_inline(body), styles["body"])],
        ],
        colWidths=[CONTENT_WIDTH],
    )
    table.setStyle(card_style(background=background, border=border, accent=accent))
    return table


def card_style(*, background, border, accent) -> TableStyle:
    return TableStyle(
        [
            ("BACKGROUND", (0, 0), (-1, -1), background),
            ("BOX", (0, 0), (-1, -1), 0.55, border),
            ("LINEBEFORE", (0, 0), (0, -1), 2.0, accent),
            ("LEFTPADDING", (0, 0), (-1, -1), 8),
            ("RIGHTPADDING", (0, 0), (-1, -1), 8),
            ("TOPPADDING", (0, 0), (-1, -1), 7),
            ("BOTTOMPADDING", (0, 0), (-1, -1), 7),
            ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ]
    )


def draw_mobile_page(
    canvas,
    doc,
    *,
    title: str,
    footer_label: str,
    page_label: str,
    accent,
    accent_rule,
    paper,
    rule,
) -> None:
    canvas.saveState()
    width, height = doc.pagesize
    canvas.setFillColor(paper)
    canvas.rect(0, 0, width, height, fill=1, stroke=0)
    canvas.setStrokeColor(accent_rule)
    canvas.setLineWidth(1.1)
    canvas.line(PAGE_MARGIN_X, height - 24, width - PAGE_MARGIN_X, height - 24)
    canvas.setStrokeColor(rule)
    canvas.setLineWidth(0.35)
    canvas.line(PAGE_MARGIN_X, 25, width - PAGE_MARGIN_X, 25)
    canvas.setFillColor(accent)
    canvas.setFont(FONT_BOLD, 7)
    canvas.drawString(PAGE_MARGIN_X, 14, footer_label[:48])
    canvas.setFont(FONT_REGULAR, 7)
    canvas.drawRightString(width - PAGE_MARGIN_X, 14, f"{page_label} {doc.page}")
    canvas.restoreState()
