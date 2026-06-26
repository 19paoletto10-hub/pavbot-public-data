#!/usr/bin/env python3
"""Create a premium mobile PDF brief for a Pavbot podcast package."""

from __future__ import annotations

import json
import re
import sys
from datetime import datetime
from html import escape
from pathlib import Path

from reportlab.lib import colors
from reportlab.platypus import HRFlowable, KeepTogether, PageBreak, Paragraph, SimpleDocTemplate, Spacer, Table, TableStyle


REPO_ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(REPO_ROOT / "scripts"))

from pavbot_pdf_theme import (  # noqa: E402
    ACCENT,
    ACCENT_DARK,
    ACCENT_LIGHT,
    AMBER,
    BORDER,
    BORDER_SOFT,
    CONTENT_WIDTH,
    LINK,
    MOBILE_PAGE_SIZE,
    MUTED,
    PAGE_MARGIN_BOTTOM,
    PAGE_MARGIN_TOP,
    PAGE_MARGIN_X,
    PAPER,
    SURFACE,
    build_mobile_styles,
    draw_mobile_page,
    markdown_inline,
    short_text,
    source_links,
    source_list_flowable,
    text_card,
)


def fail(message: str, code: int = 1) -> None:
    print(message, file=sys.stderr)
    raise SystemExit(code)


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


def split_lead_sentence(text: str) -> tuple[str, str]:
    text = re.sub(r"\s+", " ", text).strip()
    match = re.match(r"(.+?[.!?])\s+(.*)", text)
    if not match:
        return text, ""
    return match.group(1).strip(), match.group(2).strip()


def mmss(seconds: float | int | str) -> str:
    try:
        total = int(round(float(seconds)))
    except Exception:
        return "brak danych"
    return f"{total // 60}:{total % 60:02d}"


def stat_grid(rows: list[tuple[str, str]], styles: dict) -> Table:
    cells = []
    for label, value in rows:
        cells.append(
            [
                Paragraph(escape(label.upper()), styles["card_label"]),
                Paragraph(markdown_inline(value), styles["card_title"]),
            ]
        )

    grid_rows = []
    for index in range(0, len(cells), 2):
        left = cells[index]
        right = cells[index + 1] if index + 1 < len(cells) else ["", ""]
        grid_rows.append([left[0], right[0]])
        grid_rows.append([left[1], right[1]])

    table = Table(grid_rows, colWidths=[CONTENT_WIDTH / 2, CONTENT_WIDTH / 2], hAlign="LEFT")
    table.setStyle(
        TableStyle(
            [
                ("BACKGROUND", (0, 0), (-1, -1), SURFACE),
                ("BOX", (0, 0), (-1, -1), 0.55, BORDER),
                ("INNERGRID", (0, 0), (-1, -1), 0.25, BORDER_SOFT),
                ("LINEBEFORE", (0, 0), (0, -1), 2.0, ACCENT),
                ("VALIGN", (0, 0), (-1, -1), "TOP"),
                ("LEFTPADDING", (0, 0), (-1, -1), 8),
                ("RIGHTPADDING", (0, 0), (-1, -1), 8),
                ("TOPPADDING", (0, 0), (-1, -1), 5),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 5),
            ]
        )
    )
    return table


def make_story_cards(paragraphs: list[str], styles: dict) -> list:
    cards = []
    for para in paragraphs[:5]:
        title, body = split_lead_sentence(para)
        if not body:
            body = para
        cards.append(
            KeepTogether(
                [
                    text_card(
                        short_text(title, 150),
                        short_text(body, 330),
                        styles,
                        background=PAPER,
                        border=BORDER,
                        accent=ACCENT,
                    ),
                    Spacer(1, 5),
                ]
            )
        )
    return cards


def main() -> None:
    if len(sys.argv) not in (2, 3):
        fail("usage: render-podcast-brief-pdf.py PODCAST_DIR [OUTPUT_PDF]", 64)

    podcast_dir = Path(sys.argv[1])
    output_pdf = Path(sys.argv[2]) if len(sys.argv) == 3 else podcast_dir / "brief.pdf"
    script = read_text(podcast_dir / "script.md")
    sources = read_text(podcast_dir / "sources.md")
    render_json = podcast_dir / "render.json"
    render_data = json.loads(render_json.read_text(encoding="utf-8")) if render_json.is_file() else {}

    styles = build_mobile_styles(accent=ACCENT, accent_dark=ACCENT_DARK, body_size=10.25)
    paragraphs = paragraphs_from_markdown(script)
    source_used = section_links(sources, "## Źródła użyte w scenariuszu") or source_links(sources)
    checked_unused = section_links(sources, "## Źródła sprawdzone, ale niewykorzystane")
    unavailable = section_links(sources, "## Źródła niedostępne lub niejednoznaczne")

    date_label = podcast_dir.name
    topic_label = podcast_dir.parent.parent.name
    created_label = datetime.now().strftime("%Y-%m-%d %H:%M")
    title = "Pavbot Podcast Brief"

    output_pdf.parent.mkdir(parents=True, exist_ok=True)
    doc = SimpleDocTemplate(
        str(output_pdf),
        pagesize=MOBILE_PAGE_SIZE,
        leftMargin=PAGE_MARGIN_X,
        rightMargin=PAGE_MARGIN_X,
        topMargin=PAGE_MARGIN_TOP,
        bottomMargin=PAGE_MARGIN_BOTTOM,
        title=f"Pavbot {topic_label} podcast brief {date_label}",
        author="Pavbot",
        subject=f"Podcast brief: {topic_label}",
    )

    story = [
        Paragraph("PAVBOT EPISODE BRIEF", styles["kicker"]),
        Paragraph(title, styles["title"]),
        Paragraph(
            f"Temat: <b>{escape(topic_label)}</b> | Data: {escape(date_label)} | Wygenerowano: {escape(created_label)}",
            styles["subtitle"],
        ),
        HRFlowable(width="100%", thickness=0.8, color=ACCENT, spaceAfter=7),
        stat_grid(
            [
                ("Długość", mmss(render_data.get("duration_seconds", ""))),
                ("Słowa", str(render_data.get("word_count", "brak danych"))),
                ("TTS", str(render_data.get("engine_used", "brak danych"))),
                ("Model", str(render_data.get("model", "brak danych"))),
            ],
            styles,
        ),
        Spacer(1, 8),
        Paragraph("Najważniejsze informacje", styles["h2"]),
    ]
    story.extend(make_story_cards(paragraphs, styles))

    story.append(Paragraph("Kontekst redakcyjny", styles["h2"]))
    for para in paragraphs[:3]:
        story.append(Paragraph(markdown_inline(short_text(para, 480)), styles["body"]))

    story.append(PageBreak())
    story.append(Paragraph("Źródła użyte", styles["h2"]))
    if source_used:
        story.append(source_list_flowable(source_used, styles, limit=18))
    else:
        story.append(Paragraph("Brak linków źródłowych w sources.md.", styles["body"]))

    notes = []
    for label, url in checked_unused[:5]:
        notes.append(f"Sprawdzone, niewykorzystane: {label} ({url})")
    for label, url in unavailable[:5]:
        notes.append(f"Niedostępne lub niejednoznaczne: {label} ({url})")
    if notes:
        story.append(Paragraph("Uwagi źródłowe", styles["h2"]))
        for note in notes[:8]:
            story.append(Paragraph(markdown_inline(note, link_color="#1D4ED8", underline=False), styles["small"]))

    story.append(Spacer(1, 8))
    story.append(
        text_card(
            "Czytać razem ze źródłami",
            "Dokument powstał lokalnie z pakietu podcastu. Fakty i interpretacje należy weryfikować z linkami źródłowymi.",
            styles,
            background=ACCENT_LIGHT,
            border=ACCENT,
            accent=AMBER,
        )
    )

    doc.build(
        story,
        onFirstPage=lambda canvas, doc_obj: draw_mobile_page(
            canvas,
            doc_obj,
            title=title,
            footer_label=f"Podcast brief: {topic_label}",
            page_label="Strona",
            accent=ACCENT_DARK,
            accent_rule=AMBER,
        ),
        onLaterPages=lambda canvas, doc_obj: draw_mobile_page(
            canvas,
            doc_obj,
            title=title,
            footer_label=f"Podcast brief: {topic_label}",
            page_label="Strona",
            accent=ACCENT_DARK,
            accent_rule=AMBER,
        ),
    )
    print(output_pdf)


if __name__ == "__main__":
    main()
