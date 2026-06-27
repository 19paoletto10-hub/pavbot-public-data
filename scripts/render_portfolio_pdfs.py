#!/usr/bin/env python3
"""Render two polished Pavbot case-study PDFs."""

from __future__ import annotations

import argparse
import sys
from dataclasses import dataclass
from pathlib import Path

from reportlab.lib import colors
from reportlab.lib.enums import TA_CENTER, TA_LEFT
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import mm
from reportlab.platypus import (
    KeepTogether,
    PageBreak,
    Paragraph,
    SimpleDocTemplate,
    Spacer,
    Table,
    TableStyle,
)

sys.path.insert(0, str(Path(__file__).resolve().parent))

from pavbot_pdf_theme import FONT_BOLD, FONT_REGULAR, markdown_inline


REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_OUTPUT_DIR = REPO_ROOT / "output" / "pdf"
CONTENT_WIDTH = 156 * mm
SECTION_TITLE_WIDTH = 144 * mm
TWO_COLUMN_CARD_WIDTH = 74 * mm
TWO_COLUMN_CELL_WIDTH = 76 * mm
GRID_COLUMN_WIDTH = 39 * mm
DIAGRAM_STEP_WIDTH = 25.6 * mm
DIAGRAM_ARROW_WIDTH = 7 * mm

INK = colors.HexColor("#14213D")
MUTED = colors.HexColor("#536079")
SUBTLE = colors.HexColor("#7C8AA5")
PAPER = colors.HexColor("#FFFFFF")
SURFACE = colors.HexColor("#F6F8FB")
BORDER = colors.HexColor("#D8E0EA")
LINE = colors.HexColor("#E8EDF4")
AI_ACCENT = colors.HexColor("#0F766E")
AI_ACCENT_DARK = colors.HexColor("#115E59")
AI_ACCENT_LIGHT = colors.HexColor("#D9F8F1")
PRODUCT_ACCENT = colors.HexColor("#5B5BD6")
PRODUCT_ACCENT_DARK = colors.HexColor("#3730A3")
PRODUCT_ACCENT_LIGHT = colors.HexColor("#E7E8FF")
AMBER = colors.HexColor("#F59E0B")
GREEN = colors.HexColor("#16A34A")
BLUE = colors.HexColor("#2563EB")


@dataclass(frozen=True)
class Palette:
    accent: colors.Color
    accent_dark: colors.Color
    accent_light: colors.Color


@dataclass(frozen=True)
class DocumentSpec:
    filename: str
    kicker: str
    title: str
    subtitle: str
    thesis: str
    snapshot: list[tuple[str, str]]
    analysis_title: str
    analysis_intro: str
    analysis_points: list[tuple[str, str]]
    sections: list[tuple[str, str]]
    architecture_steps: list[str]
    decision_title: str
    decisions: list[tuple[str, str]]
    chips_title: str
    chips: list[str]
    evidence_title: str
    evidence: list[str]
    pitch_short: str
    pitch_long: str
    palette: Palette


def build_styles(palette: Palette) -> dict[str, ParagraphStyle]:
    base = getSampleStyleSheet()
    return {
        "kicker": ParagraphStyle(
            "PortfolioKicker",
            parent=base["Normal"],
            fontName=FONT_BOLD,
            fontSize=9,
            leading=11,
            textColor=palette.accent_dark,
            alignment=TA_CENTER,
            spaceAfter=7,
        ),
        "title": ParagraphStyle(
            "PortfolioTitle",
            parent=base["Title"],
            fontName=FONT_BOLD,
            fontSize=27,
            leading=32,
            textColor=INK,
            alignment=TA_CENTER,
            spaceAfter=8,
        ),
        "subtitle": ParagraphStyle(
            "PortfolioSubtitle",
            parent=base["Normal"],
            fontName=FONT_REGULAR,
            fontSize=10.5,
            leading=15,
            textColor=MUTED,
            alignment=TA_CENTER,
            spaceAfter=14,
        ),
        "section": ParagraphStyle(
            "PortfolioSection",
            parent=base["Heading2"],
            fontName=FONT_BOLD,
            fontSize=15,
            leading=19,
            textColor=palette.accent_dark,
            spaceBefore=7,
            spaceAfter=7,
        ),
        "section_number": ParagraphStyle(
            "PortfolioSectionNumber",
            parent=base["Normal"],
            fontName=FONT_BOLD,
            fontSize=8.2,
            leading=10,
            textColor=colors.white,
            alignment=TA_CENTER,
        ),
        "body": ParagraphStyle(
            "PortfolioBody",
            parent=base["BodyText"],
            fontName=FONT_REGULAR,
            fontSize=10.2,
            leading=14.8,
            textColor=INK,
            alignment=TA_LEFT,
            spaceAfter=6,
            splitLongWords=True,
        ),
        "small": ParagraphStyle(
            "PortfolioSmall",
            parent=base["BodyText"],
            fontName=FONT_REGULAR,
            fontSize=8.1,
            leading=10.4,
            textColor=MUTED,
            splitLongWords=True,
        ),
        "card_label": ParagraphStyle(
            "PortfolioCardLabel",
            parent=base["BodyText"],
            fontName=FONT_BOLD,
            fontSize=8.4,
            leading=10.6,
            textColor=palette.accent_dark,
            spaceAfter=3,
        ),
        "card_title": ParagraphStyle(
            "PortfolioCardTitle",
            parent=base["BodyText"],
            fontName=FONT_BOLD,
            fontSize=11.2,
            leading=14,
            textColor=INK,
            spaceAfter=4,
        ),
        "card_body": ParagraphStyle(
            "PortfolioCardBody",
            parent=base["BodyText"],
            fontName=FONT_REGULAR,
            fontSize=9.4,
            leading=13.3,
            textColor=INK,
            splitLongWords=True,
        ),
        "bullet": ParagraphStyle(
            "PortfolioBullet",
            parent=base["BodyText"],
            fontName=FONT_REGULAR,
            fontSize=9.25,
            leading=12.9,
            leftIndent=10,
            firstLineIndent=-7,
            textColor=INK,
            spaceAfter=4,
            splitLongWords=True,
        ),
        "chip": ParagraphStyle(
            "PortfolioChip",
            parent=base["BodyText"],
            fontName=FONT_BOLD,
            fontSize=8,
            leading=10,
            textColor=palette.accent_dark,
            alignment=TA_CENTER,
            splitLongWords=True,
        ),
        "diagram": ParagraphStyle(
            "PortfolioDiagram",
            parent=base["BodyText"],
            fontName=FONT_BOLD,
            fontSize=8.2,
            leading=10.5,
            textColor=INK,
            alignment=TA_CENTER,
            splitLongWords=True,
        ),
        "arrow": ParagraphStyle(
            "PortfolioArrow",
            parent=base["BodyText"],
            fontName=FONT_BOLD,
            fontSize=10,
            leading=12,
            textColor=palette.accent_dark,
            alignment=TA_CENTER,
        ),
    }


def p(text: str, style: ParagraphStyle) -> Paragraph:
    return Paragraph(markdown_inline(text, underline=False), style)


def draw_page(canvas, doc, spec: DocumentSpec) -> None:
    width, height = A4
    palette = spec.palette
    canvas.saveState()
    canvas.setFillColor(SURFACE)
    canvas.rect(0, 0, width, height, stroke=0, fill=1)
    canvas.setFillColor(PAPER)
    canvas.roundRect(16, 14, width - 32, height - 28, 12, stroke=0, fill=1)
    canvas.setFillColor(palette.accent)
    canvas.rect(16, height - 23, width - 32, 4, stroke=0, fill=1)
    canvas.setStrokeColor(LINE)
    canvas.setLineWidth(0.6)
    canvas.line(36, 30, width - 36, 30)
    canvas.setFillColor(SUBTLE)
    canvas.setFont(FONT_REGULAR, 7.5)
    canvas.drawString(42, 18, "Pavbot Intelligence - case study")
    canvas.drawRightString(width - 42, 18, f"Page {doc.page}")
    canvas.restoreState()


def card(
    title: str,
    body: str,
    styles: dict[str, ParagraphStyle],
    palette: Palette,
    *,
    label: str | None = None,
    background: colors.Color = PAPER,
    width: float = CONTENT_WIDTH,
) -> Table:
    elements = []
    if label:
        elements.append(p(label.upper(), styles["card_label"]))
    elements.append(p(title, styles["card_title"]))
    elements.append(p(body, styles["card_body"]))
    table = Table([[elements]], colWidths=[width])
    table.setStyle(
        TableStyle(
            [
                ("BACKGROUND", (0, 0), (-1, -1), background),
                ("BOX", (0, 0), (-1, -1), 0.65, BORDER),
                ("LINEBEFORE", (0, 0), (0, -1), 3, palette.accent),
                ("LEFTPADDING", (0, 0), (-1, -1), 12),
                ("RIGHTPADDING", (0, 0), (-1, -1), 12),
                ("TOPPADDING", (0, 0), (-1, -1), 10),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 10),
                ("VALIGN", (0, 0), (-1, -1), "TOP"),
                ("ROUNDEDCORNERS", [7, 7, 7, 7]),
            ]
        )
    )
    return table


def section_heading(
    number: str,
    title: str,
    styles: dict[str, ParagraphStyle],
    palette: Palette,
) -> Table:
    table = Table(
        [[p(number, styles["section_number"]), p(title, styles["section"])]],
        colWidths=[12 * mm, SECTION_TITLE_WIDTH],
        hAlign="LEFT",
    )
    table.setStyle(
        TableStyle(
            [
                ("BACKGROUND", (0, 0), (0, 0), palette.accent),
                ("LEFTPADDING", (0, 0), (0, 0), 0),
                ("RIGHTPADDING", (0, 0), (0, 0), 0),
                ("TOPPADDING", (0, 0), (0, 0), 5),
                ("BOTTOMPADDING", (0, 0), (0, 0), 5),
                ("LEFTPADDING", (1, 0), (1, 0), 8),
                ("RIGHTPADDING", (1, 0), (1, 0), 0),
                ("TOPPADDING", (1, 0), (1, 0), 0),
                ("BOTTOMPADDING", (1, 0), (1, 0), 0),
                ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
                ("ROUNDEDCORNERS", [6, 6, 6, 6]),
            ]
        )
    )
    return table


def two_column_cards(
    items: list[tuple[str, str]],
    styles: dict[str, ParagraphStyle],
    palette: Palette,
) -> Table:
    column_width = TWO_COLUMN_CARD_WIDTH
    rows = []
    for index in range(0, len(items), 2):
        row = []
        for title, body in items[index : index + 2]:
            row.append(
                card(
                    title,
                    body,
                    styles,
                    palette,
                    background=colors.HexColor("#FBFCFE"),
                    width=column_width,
                )
            )
        if len(row) == 1:
            row.append("")
        rows.append(row)
    table = Table(rows, colWidths=[TWO_COLUMN_CELL_WIDTH, TWO_COLUMN_CELL_WIDTH], hAlign="LEFT")
    table.setStyle(
        TableStyle(
            [
                ("VALIGN", (0, 0), (-1, -1), "TOP"),
                ("LEFTPADDING", (0, 0), (-1, -1), 0),
                ("RIGHTPADDING", (0, 0), (-1, -1), 4),
                ("TOPPADDING", (0, 0), (-1, -1), 4),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 7),
                ("ROUNDEDCORNERS", [7, 7, 7, 7]),
            ]
        )
    )
    return table


def architecture_diagram(
    steps: list[str],
    styles: dict[str, ParagraphStyle],
    palette: Palette,
) -> Table:
    cells = []
    widths = []
    for index, step in enumerate(steps):
        cells.append(p(f"**{index + 1:02d}** {step}", styles["diagram"]))
        widths.append(DIAGRAM_STEP_WIDTH)
        if index < len(steps) - 1:
            cells.append(p(">", styles["arrow"]))
            widths.append(DIAGRAM_ARROW_WIDTH)
    table = Table([cells], colWidths=widths)
    table.setStyle(
        TableStyle(
            [
                ("BACKGROUND", (0, 0), (-1, -1), palette.accent_light),
                ("BOX", (0, 0), (-1, -1), 0.75, palette.accent),
                ("INNERGRID", (0, 0), (-1, -1), 0.45, colors.white),
                ("LEFTPADDING", (0, 0), (-1, -1), 6),
                ("RIGHTPADDING", (0, 0), (-1, -1), 6),
                ("TOPPADDING", (0, 0), (-1, -1), 9),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 9),
                ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
                ("ROUNDEDCORNERS", [6, 6, 6, 6]),
            ]
        )
    )
    return table


def snapshot_grid(
    items: list[tuple[str, str]],
    styles: dict[str, ParagraphStyle],
    palette: Palette,
) -> Table:
    cells = []
    for label, value in items:
        cells.append(
            [
                p(label.upper(), styles["card_label"]),
                p(value, styles["small"]),
            ]
        )
    table = Table([cells], colWidths=[GRID_COLUMN_WIDTH, GRID_COLUMN_WIDTH, GRID_COLUMN_WIDTH, GRID_COLUMN_WIDTH])
    table.setStyle(
        TableStyle(
            [
                ("BACKGROUND", (0, 0), (-1, -1), colors.HexColor("#FBFCFE")),
                ("BOX", (0, 0), (-1, -1), 0.6, BORDER),
                ("INNERGRID", (0, 0), (-1, -1), 0.6, LINE),
                ("LEFTPADDING", (0, 0), (-1, -1), 7),
                ("RIGHTPADDING", (0, 0), (-1, -1), 7),
                ("TOPPADDING", (0, 0), (-1, -1), 8),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 8),
                ("VALIGN", (0, 0), (-1, -1), "TOP"),
                ("LINEABOVE", (0, 0), (-1, 0), 2.4, palette.accent),
                ("ROUNDEDCORNERS", [7, 7, 7, 7]),
            ]
        )
    )
    return table


def chip_grid(
    chips: list[str],
    styles: dict[str, ParagraphStyle],
    palette: Palette,
) -> Table:
    rows = []
    for index in range(0, len(chips), 4):
        row = [p(label, styles["chip"]) for label in chips[index : index + 4]]
        while len(row) < 4:
            row.append("")
        rows.append(row)
    table = Table(rows, colWidths=[GRID_COLUMN_WIDTH, GRID_COLUMN_WIDTH, GRID_COLUMN_WIDTH, GRID_COLUMN_WIDTH])
    table.setStyle(
        TableStyle(
            [
                ("BACKGROUND", (0, 0), (-1, -1), palette.accent_light),
                ("BOX", (0, 0), (-1, -1), 0.45, colors.white),
                ("INNERGRID", (0, 0), (-1, -1), 1.2, colors.white),
                ("LEFTPADDING", (0, 0), (-1, -1), 5),
                ("RIGHTPADDING", (0, 0), (-1, -1), 5),
                ("TOPPADDING", (0, 0), (-1, -1), 6),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 6),
                ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
                ("ROUNDEDCORNERS", [6, 6, 6, 6]),
            ]
        )
    )
    return table


def bullet_block(items: list[str], styles: dict[str, ParagraphStyle]) -> list[Paragraph]:
    return [p(f"- {item}", styles["bullet"]) for item in items]


def build_story(spec: DocumentSpec) -> list:
    styles = build_styles(spec.palette)
    story: list = []

    story.append(Spacer(1, 8))
    story.append(p(spec.kicker, styles["kicker"]))
    story.append(p(spec.title, styles["title"]))
    story.append(p(spec.subtitle, styles["subtitle"]))
    story.append(card("Główna teza", spec.thesis, styles, spec.palette, background=spec.palette.accent_light))
    story.append(Spacer(1, 9))
    story.append(snapshot_grid(spec.snapshot, styles, spec.palette))
    story.append(Spacer(1, 12))
    story.append(section_heading("01", spec.analysis_title, styles, spec.palette))
    story.append(p(spec.analysis_intro, styles["body"]))
    story.append(two_column_cards(spec.analysis_points, styles, spec.palette))

    story.append(PageBreak())
    story.append(section_heading("02", "Architektura i argumentacja", styles, spec.palette))
    story.append(architecture_diagram(spec.architecture_steps, styles, spec.palette))
    story.append(Spacer(1, 12))
    story.append(two_column_cards(spec.sections[:4], styles, spec.palette))
    story.append(Spacer(1, 7))
    story.append(section_heading("03", spec.decision_title, styles, spec.palette))
    story.append(two_column_cards(spec.decisions, styles, spec.palette))

    story.append(PageBreak())
    story.append(section_heading("04", spec.chips_title, styles, spec.palette))
    story.append(chip_grid(spec.chips, styles, spec.palette))
    story.append(Spacer(1, 12))
    story.append(section_heading("05", spec.evidence_title, styles, spec.palette))
    story.extend(bullet_block(spec.evidence, styles))
    story.append(Spacer(1, 9))
    story.append(section_heading("06", "Jak o tym mówić", styles, spec.palette))
    story.append(card("30 sekund", spec.pitch_short, styles, spec.palette, background=colors.HexColor("#FBFCFE")))
    story.append(Spacer(1, 7))
    story.append(card("2 minuty", spec.pitch_long, styles, spec.palette, background=colors.HexColor("#FBFCFE")))
    return story


def render_document(spec: DocumentSpec, output_dir: Path) -> Path:
    output_dir.mkdir(parents=True, exist_ok=True)
    output_path = output_dir / spec.filename
    doc = SimpleDocTemplate(
        str(output_path),
        pagesize=A4,
        leftMargin=27 * mm,
        rightMargin=27 * mm,
        topMargin=19 * mm,
        bottomMargin=21 * mm,
        title=spec.title,
        author="Pawel Tanski",
        subject=spec.subtitle,
    )
    story = build_story(spec)
    doc.build(
        story,
        onFirstPage=lambda canvas, doc_obj: draw_page(canvas, doc_obj, spec),
        onLaterPages=lambda canvas, doc_obj: draw_page(canvas, doc_obj, spec),
    )
    return output_path


AI_AUTOMATION_SPEC = DocumentSpec(
    filename="pavbot-ai-automation-case-study.pdf",
    kicker="AI AUTOMATION CASE STUDY",
    title="Pavbot Intelligence - System AI Automation End-to-End",
    subtitle="System end-to-end: agenci, research, dane, manifest, iOS, backend, powiadomienia i release.",
    thesis=(
        "Pavbot jest kompletnym systemem automatyzacji AI, a nie pojedynczym promptem. "
        "Łączy agentic workflows, walidowane artefakty, natywną aplikację iOS, backend "
        "powiadomień APNs oraz proces jakości i wydania."
    ),
    snapshot=[
        ("Zakres", "AI workflow + iOS + backend"),
        ("Artefakty", "JSON, PDF, audio, manifest"),
        ("Jakość", "Swift/Python tests + verifier"),
        ("Release", "App Store archive 2.0"),
    ],
    analysis_title="Perspektywa techniczna",
    analysis_intro=(
        "Z perspektywy roli AI/Automation Engineer najmocniejszy sygnał to integracja AI "
        "z klasyczną inżynierią: automatyzacja tworzy dane, ale system ma kontrakty, cache, "
        "testy, diagnostykę, deployment i przewidywalny release pipeline."
    ),
    analysis_points=[
        (
            "Najmocniejszy sygnał",
            "Potrafię zaprojektować workflow, w którym agenci tworzą użyteczne artefakty, "
            "a aplikacja i backend konsumują je stabilnie i powtarzalnie.",
        ),
        (
            "Dlaczego jest wiarygodne",
            "Repo zawiera iOS app, FastAPI notifier, manifest generator, walidatory, testy, "
            "dokumentację operacyjną i App Store archive 2.0.",
        ),
        (
            "Najlepszy angle rozmowy",
            "Mówić o produkcyjnym cyklu danych: źródła -> research -> JSON/PDF/audio -> manifest -> mobile UX -> push notifications.",
        ),
        (
            "Granice narracji",
            "Nie przedstawiać tego jako skalowanego SaaS z metrykami użytkowników. To osobisty system z realnym workflow i dojrzałą strukturą.",
        ),
    ],
    sections=[
        (
            "Czym jest Pavbot",
            "Lokalno-chmurowy system automatyzacji researchu, który zamienia cykliczne przebiegi Codex w uporządkowane raporty, dane JSON, PDF-y, podcasty i natywne ekrany iOS.",
        ),
        (
            "Problem automatyzacyjny",
            "Monitoring newsów, ofert AI/LLM, raportów i podcastów jest powtarzalny, rozproszony i podatny na utratę kontekstu. Pavbot robi z tego kontrolowany pipeline.",
        ),
        (
            "Mechanika danych",
            "Automatyzacje publikują artefakty do repo, generator tworzy publiczny manifest, a aplikacja wybiera strukturalne dane typu jobsData, researchData, pulseNewsData albo fallback PDF/Markdown.",
        ),
        (
            "Jakość działania",
            "Projekt ma testy Swift/Python, verifier workspace, cache, fallbacki, diagnostykę połączeń, blokadę produkcyjnych URL-i i powtarzalny proces archive.",
        ),
    ],
    architecture_steps=[
        "Codex automations",
        "Research artifacts",
        "Public manifest",
        "Native iOS app",
        "Notifier / APNs",
    ],
    decision_title="Decyzje techniczne, które warto podkreślać",
    decisions=[
        (
            "Manifest jako kontrakt",
            "Aplikacja nie zna szczegółów każdego przebiegu automatyzacji. Czyta manifest i wybiera najlepszy artefakt dla widoku.",
        ),
        (
            "Natywne renderowanie",
            "JSON jest zamieniany na ekrany iOS, a PDF/Markdown zostają jako fallback dla starszych lub nietypowych artefaktów.",
        ),
        (
            "Operacyjna odporność",
            "Cache, diagnostyka, testy i verifier zmniejszają ryzyko, że automatyzacja opublikuje coś nieużytecznego dla aplikacji.",
        ),
        (
            "Konfiguracja produkcyjna",
            "Wersja 2.0 wymusza produkcyjne URL-e i usuwa możliwość przypadkowego przestawienia aplikacji na stare linki.",
        ),
    ],
    chips_title="Obszary inżynierskie",
    chips=[
        "Agentic workflows",
        "Prompt/skill design",
        "Data validation",
        "Manifest-driven UX",
        "SwiftUI",
        "FastAPI",
        "APNs",
        "Caching",
        "Fallback design",
        "XcodeGen",
        "Release pipeline",
        "Operational docs",
    ],
    evidence_title="Techniczne dowody jakości",
    evidence=[
        "Natywna aplikacja iOS z zakładkami Today, Pulse Day, Jobs, Research, audio/TTS, diagnostyką i ustawieniami.",
        "Backend Pavbot Notifier obsługuje GitHub webhook, manifest diffing, rejestrację urządzeń i APNs.",
        "Artefakty publikowane są przez manifest zamiast ręcznego kopiowania danych do aplikacji.",
        "Wersja 2.0 wymusza produkcyjne URL-e i ignoruje stare lokalne ustawienia użytkownika.",
        "Walidacja obejmuje testy iOS, testy Python, workspace verifier, diff check oraz archive App Store Connect.",
    ],
    pitch_short=(
        "Pavbot to system AI automation end-to-end. Agenci Codex wykonują research, generują strukturalne dane, PDF-y i audio, manifest publikuje wyniki, a natywna aplikacja iOS pokazuje je z cache, fallbackami i powiadomieniami."
    ),
    pitch_long=(
        "Najważniejsze w Pavbot jest to, że AI nie kończy się na odpowiedzi w czacie. Zbudowałem pipeline, w którym automatyzacje mają kontrakty tematów, zapisują raporty i dane, generator tworzy manifest, backend wykrywa nowe publikacje i może wysyłać APNs, a aplikacja iOS renderuje wyniki jako produkt. To pokazuje projektowanie agentów, integrację systemów, walidację danych, mobile UX i operacyjne myślenie o jakości."
    ),
    palette=Palette(AI_ACCENT, AI_ACCENT_DARK, AI_ACCENT_LIGHT),
)


PRODUCT_FOUNDER_SPEC = DocumentSpec(
    filename="pavbot-product-founder-case-study.pdf",
    kicker="PRODUCT / FOUNDER CASE STUDY",
    title="Pavbot Intelligence - Produkt AI Od Pomysłu Do Release",
    subtitle="Case study osobistego produktu AI: problem, UX, automatyzacja, operacje i App Store readiness.",
    thesis=(
        "Pavbot pokazuje zdolność samodzielnego zbudowania produktu AI: od rozpoznania "
        "powtarzalnego problemu informacyjnego, przez mobile-first doświadczenie, po backend, "
        "jakość, dokumentację i przygotowanie wydania."
    ),
    snapshot=[
        ("Pozycja", "personal AI intelligence"),
        ("UX", "native tabs + audio"),
        ("Zaufanie", "cache + diagnostics"),
        ("Release", "version 2.0 archive"),
    ],
    analysis_title="Analiza narracji produktowej",
    analysis_intro=(
        "Z perspektywy Product/Founder najmocniejszy sygnał to ownership całego cyklu: "
        "problem, przepływ wartości, UX, niezawodność, dystrybucja i przygotowanie do wydania. "
        "Pavbot jest produktem osobistym, ale ma dojrzałe elementy systemu produkcyjnego."
    ),
    analysis_points=[
        (
            "Najmocniejszy sygnał",
            "Potrafię przełożyć własny problem informacyjny na działający produkt, nie tylko na prototyp techniczny.",
        ),
        (
            "Dlaczego jest wiarygodne",
            "Są realne ekrany iOS, powiadomienia, cache, historia, audio, dokumentacja, release notes i archive 2.0.",
        ),
        (
            "Najlepszy angle rozmowy",
            "Mówić o produkcie jako o osobistym centrum inteligencji operacyjnej, które skraca drogę od informacji do decyzji.",
        ),
        (
            "Czego nie obiecywać",
            "Nie dopisywać przychodów ani adopcji. Siłą projektu jest wykonanie, spójność i gotowość do pokazania.",
        ),
    ],
    sections=[
        (
            "Produkt w jednym zdaniu",
            "Pavbot to osobisty system inteligencji operacyjnej na iPhone: codziennie porządkuje newsy, oferty AI/LLM, pogodę, research, audio i raporty.",
        ),
        (
            "Dla kogo i po co",
            "Dla osoby, która chce mieć aktualny, źródłowy i mobilny przegląd tematów bez ręcznego sprawdzania wielu miejsc, plików i feedów.",
        ),
        (
            "Wartość produktowa",
            "Użytkownik dostaje krótszą drogę do decyzji: najnowszy kontekst, historię, zapisywanie treści, podcasty/TTS, powiadomienia i czytelne fallbacki.",
        ),
        (
            "Od prototypu do release",
            "Projekt przeszedł od automatyzacji researchu do aplikacji iOS, backendu notifiera, produkcyjnych URL-i, testów, dokumentacji i archive 2.0.",
        ),
    ],
    architecture_steps=[
        "User need",
        "AI workflow",
        "Curated artifacts",
        "Mobile product",
        "Release loop",
    ],
    decision_title="Decyzje produktowe, które warto podkreślać",
    decisions=[
        (
            "Nie surowe pliki, tylko produkt",
            "Użytkownik dostaje zakładki, karty, historię, zapisane treści i audio, zamiast przeglądać strukturę repozytorium.",
        ),
        (
            "Mobile-first konsumpcja",
            "Pavbot jest zaprojektowany pod szybkie sprawdzenie kontekstu na telefonie, z fallbackami na gorszą sieć.",
        ),
        (
            "Zaufanie i prostota",
            "Konfiguracja 2.0 blokuje edycję produkcyjnych linków, więc użytkownik nie może przypadkowo zepsuć źródła danych.",
        ),
        (
            "Ownership od A do Z",
            "Projekt obejmuje ideę, UX, backend, jakość, dokumenty operacyjne i przygotowanie archive do App Store Connect.",
        ),
    ],
    chips_title="Obszary produktowe",
    chips=[
        "Problem framing",
        "UX thinking",
        "Mobile-first design",
        "Content strategy",
        "Product ops",
        "Release ownership",
        "Quality bar",
        "User trust",
        "Notifications",
        "Offline fallback",
        "Documentation",
        "Founder mindset",
    ],
    evidence_title="Dowody product ownership",
    evidence=[
        "Aplikacja nie pokazuje surowego repo, tylko natywne doświadczenia: Jobs, Research, Pulse Day, Today i audio.",
        "Produkt ma decyzje UX: historia 48h, zapisywanie treści, mini-player, diagnostyka i jasne komunikaty cache.",
        "Konfiguracja linków została uproszczona w wersji 2.0: użytkownik widzi produkcyjne wartości, ale ich nie psuje.",
        "Workflow obejmuje publikację, powiadomienia, release checklist, App Store archive i dokumentację operacyjną.",
        "Projekt jest uczciwie pozycjonowany jako osobisty system AI, bez niezweryfikowanych metryk biznesowych.",
    ],
    pitch_short=(
        "Pavbot to mój osobisty produkt AI, który zamienia codzienny chaos informacyjny w mobilne centrum decyzji. Łączy automatyczny research, newsy, Jobs intelligence, audio i powiadomienia w jednej aplikacji iOS."
    ),
    pitch_long=(
        "Patrzę na Pavbot jak na produkt, nie tylko technologię. Zidentyfikowałem powtarzalny problem: za dużo źródeł, za mało uporządkowanego kontekstu na telefonie. Zbudowałem workflow, który cyklicznie tworzy raporty i dane, a aplikacja zamienia je w czytelne ekrany, historię, audio i powiadomienia. Najważniejsze jest dla mnie to, że projekt ma pełny cykl: idea, UX, backend, testy, dokumentacja, release i gotowość do pokazania użytkownikowi."
    ),
    palette=Palette(PRODUCT_ACCENT, PRODUCT_ACCENT_DARK, PRODUCT_ACCENT_LIGHT),
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Render Pavbot case-study PDFs.")
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=DEFAULT_OUTPUT_DIR,
        help="Directory for generated PDFs.",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    outputs = [
        render_document(AI_AUTOMATION_SPEC, args.output_dir),
        render_document(PRODUCT_FOUNDER_SPEC, args.output_dir),
    ]
    for output in outputs:
        print(output)


if __name__ == "__main__":
    main()
