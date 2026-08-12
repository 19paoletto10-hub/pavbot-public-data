from __future__ import annotations

import importlib.util
import re
import sys
from html import escape
from pathlib import Path

from reportlab.lib import colors
from reportlab.lib.styles import ParagraphStyle
from reportlab.platypus import ListFlowable, ListItem, Paragraph


def _load_theme() -> object:
    repo_root = Path(__file__).resolve().parents[5]
    theme_path = repo_root / "scripts" / "pavbot_pdf_theme.py"
    spec = importlib.util.spec_from_file_location("pavbot_pdf_theme", theme_path)
    if spec is None or spec.loader is None:
        raise ImportError(f"unable to load theme from {theme_path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules["pavbot_pdf_theme"] = module
    spec.loader.exec_module(module)
    return module


theme = _load_theme()

if not hasattr(theme, "BORDER_SOFT"):
    theme.BORDER_SOFT = colors.HexColor("#E2E8F0")


_original_markdown_inline = theme.markdown_inline


def markdown_inline(text, *args, **kwargs):
    return _original_markdown_inline(text)


theme.markdown_inline = markdown_inline


_original_build_mobile_styles = theme.build_mobile_styles
_original_draw_mobile_page = theme.draw_mobile_page


def build_mobile_styles(*args, **kwargs):
    styles = _original_build_mobile_styles(*args, **kwargs)
    if "card_label" not in styles:
        styles["card_label"] = ParagraphStyle(
            "PavbotCardLabel",
            parent=styles["small"],
            fontSize=7.1,
            leading=8.2,
            textColor=theme.MUTED,
            spaceAfter=1,
            splitLongWords=True,
        )
    return styles


theme.build_mobile_styles = build_mobile_styles


def short_text(text, limit: int = 420) -> str:
    value = re.sub(r"\s+", " ", str(text or "")).strip()
    if len(value) <= limit:
        return value
    cut = value[:limit].rsplit(" ", 1)[0].rstrip(" ,;:")
    return f"{cut}..."


def source_links(text: str) -> list[tuple[str, str]]:
    return [(label.strip(), url.strip()) for label, url in re.findall(r"\[([^\]]+)\]\((https?://[^)]+)\)", text or "")]


def source_list_flowable(links: list[tuple[str, str]], styles: dict, limit: int = 18):
    items = []
    for label, url in links[:limit]:
        para = Paragraph(
            f'<a href="{escape(url, quote=True)}"><font color="#1D4ED8">{escape(label)}</font></a>',
            styles["body"],
        )
        items.append(ListItem(para))
    return ListFlowable(items, bulletType="bullet", leftIndent=10)


def draw_mobile_page(canvas, doc, *, title, footer_label, page_label, accent, accent_rule, paper=None, rule=None):
    if paper is None:
        paper = theme.PAPER
    if rule is None:
        rule = theme.BORDER
    return _original_draw_mobile_page(
        canvas,
        doc,
        title=title,
        footer_label=footer_label,
        page_label=page_label,
        accent=accent,
        accent_rule=accent_rule,
        paper=paper,
        rule=rule,
    )


theme.short_text = short_text
theme.source_links = source_links
theme.source_list_flowable = source_list_flowable
theme.draw_mobile_page = draw_mobile_page
