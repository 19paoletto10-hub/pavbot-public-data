#!/usr/bin/env python3
"""Render a Pavbot Markdown research report to a polished mobile PDF."""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

from reportlab.platypus import HRFlowable, KeepTogether, Paragraph, SimpleDocTemplate, Spacer

sys.path.insert(0, str(Path(__file__).resolve().parent))

from pavbot_pdf_theme import (
    ACCENT,
    ACCENT_DARK,
    ACCENT_LIGHT,
    AMBER,
    BORDER,
    MOBILE_PAGE_SIZE,
    PAGE_MARGIN_BOTTOM,
    PAGE_MARGIN_TOP,
    PAGE_MARGIN_X,
    PAPER,
    build_mobile_styles,
    draw_mobile_page,
    key_value_card,
    markdown_inline,
    markdown_source_inline,
    text_card,
)


SECTION_LABELS = {
    "scope checked": "Zakres sprawdzony",
    "summary": "Podsumowanie",
    "executive summary": "Executive summary",
    "new facts": "Nowe fakty",
    "changes since previous run": "Zmiany od poprzedniego przebiegu",
    "risks or uncertainty": "Ryzyka i niepewność",
    "recommended actions": "Rekomendowane działania",
    "sources": "Źródła",
}
METADATA_KEYS = {"date", "status"}


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
    for line in lines[:14]:
        stripped = line.strip()
        if ":" not in stripped or stripped.startswith("- "):
            continue
        key, value = stripped.split(":", 1)
        key = key.strip().lower()
        if key in METADATA_KEYS:
            metadata[key] = value.strip()
    return metadata


def is_metadata_line(stripped: str) -> bool:
    if ":" not in stripped or stripped.startswith("- "):
        return False
    key = stripped.split(":", 1)[0].strip().lower()
    return key in METADATA_KEYS


def normalized_heading(value: str) -> str:
    return value.strip().rstrip(":").lower()


def display_heading(value: str) -> str:
    return SECTION_LABELS.get(normalized_heading(value), value)


def is_sources_section(value: str) -> bool:
    return normalized_heading(value) in {"źródła", "sources"}


def starts_new_block(stripped: str) -> bool:
    return not stripped or stripped.startswith("#") or stripped.startswith("|") or stripped.startswith("- ")


def collect_paragraph(lines: list[str], start: int) -> tuple[str, int]:
    parts: list[str] = []
    i = start
    while i < len(lines):
        stripped = lines[i].strip()
        if starts_new_block(stripped):
            break
        if is_metadata_line(stripped):
            break
        parts.append(stripped)
        i += 1
    return " ".join(parts), i


def collect_list_item(lines: list[str], start: int) -> tuple[str, int]:
    parts = [lines[start].strip()[2:].strip()]
    i = start + 1
    while i < len(lines):
        stripped = lines[i].strip()
        if starts_new_block(stripped) or is_metadata_line(stripped):
            break
        parts.append(stripped)
        i += 1
    return " ".join(parts), i


def make_table_cards(rows: list[list[str]], styles: dict) -> list:
    if not rows:
        return []
    headers = rows[0]
    body_rows = rows[1:] or rows
    cards = []
    for row in body_rows:
        card = key_value_card(headers, row, styles, background=PAPER, accent=ACCENT)
        cards.append(KeepTogether([card, Spacer(1, 5)]))
    return cards


def append_title(story: list, title: str, topic_name: str | None, metadata: dict[str, str], styles: dict) -> None:
    subtitle_bits = [
        bit
        for bit in [
            f"Temat: {topic_name}" if topic_name else "",
            f"Date: {metadata['date']}" if metadata.get("date") else "",
            f"Status: {metadata['status']}" if metadata.get("status") else "",
        ]
        if bit
    ]
    story.append(Paragraph("PAVBOT RESEARCH BRIEF", styles["kicker"]))
    story.append(Paragraph(markdown_inline(title), styles["title"]))
    if subtitle_bits:
        story.append(Paragraph(" | ".join(subtitle_bits), styles["subtitle"]))
    story.append(HRFlowable(width="100%", thickness=0.8, color=ACCENT, spaceAfter=7))


def parse_markdown(markdown_text: str, topic_name: str | None) -> tuple[str, list]:
    styles = build_mobile_styles(accent=ACCENT, accent_dark=ACCENT_DARK, body_size=10.65)
    story: list = []
    lines = markdown_text.splitlines()
    metadata = read_metadata(lines)
    title = topic_name or "Pavbot Research Report"
    title_seen = False
    current_section = ""
    summary_callout_used = False
    i = 0

    while i < len(lines):
        line = lines[i].rstrip()
        stripped = line.strip()

        if not stripped:
            story.append(Spacer(1, 3))
            i += 1
            continue

        if is_metadata_line(stripped):
            i += 1
            continue

        if stripped.startswith("|"):
            rows, i = collect_table(lines, i)
            story.extend(make_table_cards(rows, styles))
            continue

        if stripped.startswith("# "):
            title = stripped[2:].strip()
            append_title(story, title, topic_name, metadata, styles)
            title_seen = True
            current_section = ""
            i += 1
            continue

        if not title_seen:
            append_title(story, title, topic_name, metadata, styles)
            title_seen = True

        if stripped.startswith("## "):
            heading = stripped[3:].strip()
            current_section = normalized_heading(heading)
            story.append(Paragraph(markdown_inline(display_heading(heading)), styles["h2"]))
            i += 1
            continue

        if stripped.startswith("### "):
            heading = stripped[4:].strip()
            current_section = normalized_heading(heading)
            story.append(Paragraph(markdown_inline(display_heading(heading)), styles["h3"]))
            i += 1
            continue

        if stripped.startswith("- "):
            item, i = collect_list_item(lines, i)
            markup = markdown_source_inline(item) if is_sources_section(current_section) else markdown_inline(item)
            story.append(Paragraph("- " + markup, styles["bullet"]))
            continue

        paragraph, i = collect_paragraph(lines, i)
        if not paragraph:
            continue
        if current_section in {"podsumowanie", "summary", "executive summary"} and not summary_callout_used:
            story.append(text_card("NAJWAŻNIEJSZE", paragraph, styles, background=ACCENT_LIGHT, border=ACCENT, accent=AMBER))
            story.append(Spacer(1, 6))
            summary_callout_used = True
            continue
        markup = markdown_source_inline(paragraph) if is_sources_section(current_section) else markdown_inline(paragraph)
        story.append(Paragraph(markup, styles["body"]))

    return title, story


def render_pdf(markdown_report: Path, pdf_output: Path, topic_name: str | None = None) -> None:
    markdown_text = markdown_report.read_text(encoding="utf-8")
    title, story = parse_markdown(markdown_text, topic_name)
    pdf_output.parent.mkdir(parents=True, exist_ok=True)
    doc = SimpleDocTemplate(
        str(pdf_output),
        pagesize=MOBILE_PAGE_SIZE,
        leftMargin=PAGE_MARGIN_X,
        rightMargin=PAGE_MARGIN_X,
        topMargin=PAGE_MARGIN_TOP,
        bottomMargin=PAGE_MARGIN_BOTTOM,
        title=title,
        author="Pavbot",
        subject=f"Pavbot research report: {topic_name or markdown_report.stem}",
    )
    doc.build(
        story,
        onFirstPage=lambda canvas, doc_obj: draw_mobile_page(
            canvas,
            doc_obj,
            title=title,
            footer_label=title,
            page_label="Page",
            accent=ACCENT_DARK,
            accent_rule=AMBER,
            paper=PAPER,
            rule=BORDER,
        ),
        onLaterPages=lambda canvas, doc_obj: draw_mobile_page(
            canvas,
            doc_obj,
            title=title,
            footer_label=title,
            page_label="Page",
            accent=ACCENT_DARK,
            accent_rule=AMBER,
            paper=PAPER,
            rule=BORDER,
        ),
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
