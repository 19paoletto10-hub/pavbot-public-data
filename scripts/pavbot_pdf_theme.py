"""Shared premium mobile PDF theme helpers for Pavbot renderers."""

from __future__ import annotations

import html
import re
from pathlib import Path

from reportlab.lib import colors
from reportlab.lib.enums import TA_CENTER, TA_LEFT
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import mm
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import ListFlowable, ListItem, Paragraph, Table, TableStyle


MOBILE_PAGE_SIZE = (390, 844)
PAGE_MARGIN_X = 20
PAGE_MARGIN_TOP = 27
PAGE_MARGIN_BOTTOM = 28
CONTENT_WIDTH = MOBILE_PAGE_SIZE[0] - (PAGE_MARGIN_X * 2)

INK = colors.HexColor("#111827")
MUTED = colors.HexColor("#64748B")
SUBTLE = colors.HexColor("#94A3B8")
ACCENT = colors.HexColor("#0F766E")
ACCENT_DARK = colors.HexColor("#115E59")
ACCENT_LIGHT = colors.HexColor("#CCFBF1")
AMBER = colors.HexColor("#B45309")
AMBER_LIGHT = colors.HexColor("#FEF3C7")
SURFACE = colors.HexColor("#F8FAFC")
PAPER = colors.HexColor("#FFFFFF")
PAPER_WARM = colors.HexColor("#FFFDF5")
BORDER = colors.HexColor("#CBD5E1")
BORDER_SOFT = colors.HexColor("#E2E8F0")
LINK = colors.HexColor("#1D4ED8")


def _first_existing(paths: list[str]) -> Path | None:
    for raw_path in paths:
        path = Path(raw_path).expanduser()
        if path.is_file():
            return path
    return None


def register_fonts(prefix: str = "PavbotPremium") -> tuple[str, str]:
    regular = _first_existing(
        [
            "~/.cache/codex-runtimes/codex-primary-runtime/dependencies/native/libreoffice-headless/libreoffice/LibreOfficeDev.app/Contents/Resources/fonts/truetype/NotoSans-Regular.ttf",
            "~/.cache/codex-runtimes/codex-primary-runtime/dependencies/native/libreoffice-headless/libreoffice/LibreOfficeDev.app/Contents/Resources/fonts/truetype/DejaVuSans.ttf",
            "/System/Library/Fonts/Supplemental/Arial Unicode.ttf",
            "/System/Library/Fonts/Supplemental/Arial.ttf",
            "/Library/Fonts/Arial.ttf",
            "/System/Library/Fonts/Supplemental/DejaVu Sans.ttf",
        ]
    )
    bold = _first_existing(
        [
            "~/.cache/codex-runtimes/codex-primary-runtime/dependencies/native/libreoffice-headless/libreoffice/LibreOfficeDev.app/Contents/Resources/fonts/truetype/NotoSans-Bold.ttf",
            "~/.cache/codex-runtimes/codex-primary-runtime/dependencies/native/libreoffice-headless/libreoffice/LibreOfficeDev.app/Contents/Resources/fonts/truetype/DejaVuSans-Bold.ttf",
            "/System/Library/Fonts/Supplemental/Arial Bold.ttf",
            "/Library/Fonts/Arial Bold.ttf",
            "/System/Library/Fonts/Supplemental/DejaVu Sans Bold.ttf",
        ]
    )

    if regular:
        regular_name = f"{prefix}-Regular"
        pdfmetrics.registerFont(TTFont(regular_name, str(regular)))
        if bold:
            bold_name = f"{prefix}-Bold"
            pdfmetrics.registerFont(TTFont(bold_name, str(bold)))
            return regular_name, bold_name
        return regular_name, regular_name
    return "Helvetica", "Helvetica-Bold"


FONT_REGULAR, FONT_BOLD = register_fonts()


def clean_text(text: str) -> str:
    return re.sub(r"\s+", " ", text).strip()


def short_text(text: str, limit: int = 420) -> str:
    text = clean_text(text)
    if len(text) <= limit:
        return text
    window = text[:limit].rstrip()
    sentence_end = max(window.rfind("."), window.rfind("?"), window.rfind("!"))
    if sentence_end >= min(90, int(limit * 0.35)):
        return window[: sentence_end + 1]
    cut = window.rsplit(" ", 1)[0].rstrip(" ,;:-")
    return f"{cut}..."


def markdown_inline(text: str, link_color: str = "#1D4ED8", underline: bool = True) -> str:
    escaped = html.escape(clean_text(text))
    escaped = re.sub(r"\*\*(.+?)\*\*", r"<b>\1</b>", escaped)
    escaped = re.sub(r"`([^`]+)`", rf"<font name='{FONT_REGULAR}'>\1</font>", escaped)

    def link_repl(match: re.Match[str]) -> str:
        label = match.group(1)
        url = html.escape(match.group(2), quote=True)
        body = f'<font color="{link_color}">{label}</font>'
        if underline:
            body = f"<u>{body}</u>"
        return f'<a href="{url}">{body}</a>'

    return re.sub(r"\[([^\]]+)\]\((https?://[^)]+)\)", link_repl, escaped)


def markdown_source_inline(text: str, link_color: str = "#1D4ED8") -> str:
    escaped = html.escape(clean_text(text))
    escaped = re.sub(r"\*\*(.+?)\*\*", r"<b>\1</b>", escaped)
    escaped = re.sub(r"`([^`]+)`", rf"<font name='{FONT_REGULAR}'>\1</font>", escaped)

    def link_repl(match: re.Match[str]) -> str:
        label = clean_text(match.group(1)) or clean_text(match.group(2))
        safe_label = html.escape(label)
        safe_url = html.escape(match.group(2).strip(), quote=True)
        visible_url = html.escape(match.group(2).strip())
        label_markup = (
            f'<a href="{safe_url}"><u><font color="{link_color}">{safe_label}</font></u></a>'
        )
        url_markup = (
            f'<a href="{safe_url}"><u><font color="{link_color}">{visible_url}</font></u></a>'
        )
        return (
            f"{label_markup}"
            f'<font color="#64748B"> (</font>{url_markup}<font color="#64748B">)</font>'
        )

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


def build_mobile_styles(
    *,
    accent: colors.Color = ACCENT,
    accent_dark: colors.Color = ACCENT_DARK,
    body_size: float = 10.35,
) -> dict[str, ParagraphStyle]:
    base = getSampleStyleSheet()
    return {
        "kicker": ParagraphStyle(
            "PavbotPremiumKicker",
            parent=base["Normal"],
            fontName=FONT_BOLD,
            fontSize=8.2,
            leading=10.2,
            alignment=TA_CENTER,
            textColor=accent_dark,
            spaceAfter=5,
            splitLongWords=True,
        ),
        "title": ParagraphStyle(
            "PavbotPremiumTitle",
            parent=base["Title"],
            fontName=FONT_BOLD,
            fontSize=20.4,
            leading=24.5,
            alignment=TA_CENTER,
            textColor=INK,
            spaceAfter=6,
            splitLongWords=True,
        ),
        "subtitle": ParagraphStyle(
            "PavbotPremiumSubtitle",
            parent=base["Normal"],
            fontName=FONT_REGULAR,
            fontSize=8.3,
            leading=11.3,
            alignment=TA_CENTER,
            textColor=MUTED,
            spaceAfter=9,
            splitLongWords=True,
        ),
        "h2": ParagraphStyle(
            "PavbotPremiumH2",
            parent=base["Heading2"],
            fontName=FONT_BOLD,
            fontSize=13.2,
            leading=16.4,
            textColor=accent_dark,
            spaceBefore=10,
            spaceAfter=5,
            splitLongWords=True,
        ),
        "h3": ParagraphStyle(
            "PavbotPremiumH3",
            parent=base["Heading3"],
            fontName=FONT_BOLD,
            fontSize=11.8,
            leading=14.8,
            textColor=INK,
            spaceBefore=7,
            spaceAfter=4,
            splitLongWords=True,
        ),
        "body": ParagraphStyle(
            "PavbotPremiumBody",
            parent=base["BodyText"],
            fontName=FONT_REGULAR,
            fontSize=body_size,
            leading=body_size + 4.2,
            textColor=INK,
            alignment=TA_LEFT,
            spaceAfter=5,
            splitLongWords=True,
        ),
        "bullet": ParagraphStyle(
            "PavbotPremiumBullet",
            parent=base["BodyText"],
            fontName=FONT_REGULAR,
            fontSize=max(9.9, body_size - 0.2),
            leading=body_size + 4,
            textColor=INK,
            leftIndent=12,
            firstLineIndent=-7,
            spaceAfter=4,
            splitLongWords=True,
        ),
        "small": ParagraphStyle(
            "PavbotPremiumSmall",
            parent=base["BodyText"],
            fontName=FONT_REGULAR,
            fontSize=7.6,
            leading=9.6,
            textColor=MUTED,
            splitLongWords=True,
        ),
        "card_label": ParagraphStyle(
            "PavbotPremiumCardLabel",
            parent=base["BodyText"],
            fontName=FONT_BOLD,
            fontSize=7.8,
            leading=9.8,
            textColor=accent_dark,
            splitLongWords=True,
        ),
        "card_title": ParagraphStyle(
            "PavbotPremiumCardTitle",
            parent=base["BodyText"],
            fontName=FONT_BOLD,
            fontSize=10.1,
            leading=13,
            textColor=INK,
            spaceAfter=3,
            splitLongWords=True,
        ),
        "card_body": ParagraphStyle(
            "PavbotPremiumCardBody",
            parent=base["BodyText"],
            fontName=FONT_REGULAR,
            fontSize=9.65,
            leading=13.1,
            textColor=INK,
            splitLongWords=True,
        ),
        "link": ParagraphStyle(
            "PavbotPremiumLink",
            parent=base["BodyText"],
            fontName=FONT_REGULAR,
            fontSize=7.6,
            leading=9.8,
            textColor=LINK,
            splitLongWords=True,
        ),
    }


def key_value_card(
    headers: list[str],
    row: list[str],
    styles: dict[str, ParagraphStyle],
    *,
    background: colors.Color = PAPER,
    accent: colors.Color = ACCENT,
) -> Table:
    normalized = row + [""] * (len(headers) - len(row))
    data = [
        [
            Paragraph(markdown_inline(header), styles["card_label"]),
            Paragraph(markdown_inline(value), styles["card_body"]),
        ]
        for header, value in zip(headers, normalized)
    ]
    label_width = min(118, CONTENT_WIDTH * 0.38)
    table = Table(data, colWidths=[label_width, CONTENT_WIDTH - label_width], hAlign="LEFT")
    table.setStyle(
        TableStyle(
            [
                ("BACKGROUND", (0, 0), (-1, -1), background),
                ("BACKGROUND", (0, 0), (0, -1), SURFACE),
                ("BOX", (0, 0), (-1, -1), 0.55, BORDER),
                ("LINEBEFORE", (0, 0), (0, -1), 2.0, accent),
                ("INNERGRID", (0, 0), (-1, -1), 0.25, BORDER_SOFT),
                ("VALIGN", (0, 0), (-1, -1), "TOP"),
                ("LEFTPADDING", (0, 0), (-1, -1), 7),
                ("RIGHTPADDING", (0, 0), (-1, -1), 7),
                ("TOPPADDING", (0, 0), (-1, -1), 5.5),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 5.5),
            ]
        )
    )
    return table


def text_card(
    title: str,
    body: str,
    styles: dict[str, ParagraphStyle],
    *,
    background: colors.Color = PAPER,
    border: colors.Color = BORDER,
    accent: colors.Color | None = None,
) -> Table:
    rows = [[Paragraph(markdown_inline(title), styles["card_title"])]]
    if body:
        rows.append([Paragraph(markdown_inline(body), styles["card_body"])])
    table = Table(rows, colWidths=[CONTENT_WIDTH], hAlign="LEFT")
    style_items = [
        ("BACKGROUND", (0, 0), (-1, -1), background),
        ("BOX", (0, 0), (-1, -1), 0.55, border),
        ("LEFTPADDING", (0, 0), (-1, -1), 9),
        ("RIGHTPADDING", (0, 0), (-1, -1), 9),
        ("TOPPADDING", (0, 0), (-1, -1), 8),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 8),
    ]
    if accent is not None:
        style_items.append(("LINEBEFORE", (0, 0), (0, -1), 2.0, accent))
    table.setStyle(TableStyle(style_items))
    return table


def source_list_flowable(
    links: list[tuple[str, str]],
    styles: dict[str, ParagraphStyle],
    *,
    limit: int = 30,
) -> ListFlowable:
    items = []
    for label, url in unique_links(links)[:limit]:
        items.append(ListItem(Paragraph(markdown_source_inline(f"[{label}]({url})"), styles["link"])))
    return ListFlowable(items, bulletType="bullet", leftIndent=12)


def draw_mobile_page(
    canvas,
    doc,
    *,
    title: str,
    footer_label: str = "Pavbot",
    page_label: str = "Page",
    accent: colors.Color = ACCENT,
    accent_rule: colors.Color = AMBER,
    paper: colors.Color = PAPER,
    rule: colors.Color = BORDER_SOFT,
) -> None:
    canvas.saveState()
    width, height = doc.pagesize
    canvas.setFillColor(paper)
    canvas.rect(0, 0, width, height, stroke=0, fill=1)
    canvas.setFillColor(accent)
    canvas.rect(0, height - 6, width, 6, stroke=0, fill=1)
    canvas.setFillColor(accent_rule)
    canvas.rect(0, height - 6, width, 1.1, stroke=0, fill=1)
    canvas.setStrokeColor(rule)
    canvas.setLineWidth(0.45)
    canvas.line(PAGE_MARGIN_X, 18, width - PAGE_MARGIN_X, 18)
    canvas.setFillColor(MUTED)
    canvas.setFont(FONT_REGULAR, 7)
    canvas.drawString(PAGE_MARGIN_X, 8, footer_label[:68])
    canvas.drawRightString(width - PAGE_MARGIN_X, 8, f"{page_label} {doc.page}")
    canvas.restoreState()
