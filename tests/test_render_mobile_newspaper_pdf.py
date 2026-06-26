from __future__ import annotations

import importlib.util
import tempfile
import unittest
from pathlib import Path

import pdfplumber


def load_renderer():
    module_path = (
        Path(__file__).resolve().parents[1]
        / "research"
        / "aktualne-wydarzenia-mobile"
        / "tools"
        / "render_mobile_newspaper_pdf.py"
    )
    spec = importlib.util.spec_from_file_location("render_mobile_newspaper_pdf", module_path)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


class RenderMobileNewspaperPdfTest(unittest.TestCase):
    def test_render_newspaper_pdf_contains_required_sections_articles_and_sources(self) -> None:
        renderer = load_renderer()

        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            report = tmp_path / "2026-06-23-1015.md"
            output = tmp_path / "2026-06-23-1015-newspaper.pdf"
            report.write_text(
                """# Pavbot Aktualne Wydarzenia

Date: 2026-06-23
Status: Material update

## Gazeta

### Ogólne

#### Poranny obraz dnia
Lead: Najważniejsze decyzje publiczne układają się dziś w mapę ryzyk dla obywateli.
Fakty:
- Rząd opublikował komunikat o bezpieczeństwie. [KPRM](https://www.gov.pl/example)
Analiza: To temat otwierający wydanie, bo wyznacza ton pozostałych sekcji.

### Polska

#### Instytucje publiczne i obywatele
Lead: Krajowe komunikaty wymagają oddzielenia faktów od politycznego szumu.
Fakty:
- Sejm opublikował porządek obrad. [Sejm](https://www.sejm.gov.pl/example)
Analiza: Dla odbiorcy ważny jest praktyczny skutek decyzji, nie sama konferencja.

### Polityka

#### Spór polityczny bez skrótów
Lead: Spór wewnętrzny ma znaczenie, jeśli zmienia działanie instytucji.
Fakty:
- Kancelaria Prezydenta opublikowała plan aktywności. [Prezydent](https://www.prezydent.pl/example)
Analiza: Najważniejsze jest, czy deklaracje przełożą się na decyzje.

### Sprawy zagraniczne

#### Dyplomacja i bezpieczeństwo
Lead: Wydarzenia międzynarodowe wpływają bezpośrednio na polską perspektywę.
Fakty:
- NATO opublikowało komunikat o konsultacjach. [NATO](https://www.nato.int/example)
Analiza: To pokazuje znaczenie sojuszy i komunikacji kryzysowej.

### Technologia

#### Technologia w państwie
Lead: Infrastruktura cyfrowa coraz częściej jest częścią polityki publicznej.
Fakty:
- Komisja Europejska opisała nowe działania cyfrowe. [Komisja Europejska](https://commission.europa.eu/example)
Analiza: Technologia jest tu narzędziem administracji i bezpieczeństwa.
""",
                encoding="utf-8",
            )

            renderer.render_newspaper_pdf(
                report,
                output,
                topic_name="aktualne-wydarzenia-mobile",
            )

            self.assertTrue(output.exists())
            self.assertGreater(output.stat().st_size, 12_000)
            with pdfplumber.open(output) as pdf:
                first_page = pdf.pages[0]
                text = "\n".join(page.extract_text() or "" for page in pdf.pages)

        self.assertLessEqual(first_page.width, 430)
        self.assertGreaterEqual(first_page.height, 780)
        for expected in (
            "PAVBOT",
            "Ogólne",
            "Polska",
            "Polityka",
            "Sprawy zagraniczne",
            "Technologia",
            "Poranny obraz dnia",
            "KPRM",
            "Komisja Europejska",
        ):
            with self.subTest(expected=expected):
                self.assertIn(expected, text)
        self.assertEqual(text.count("Poranny obraz dnia"), 1)

    def test_missing_newspaper_section_uses_no_material_change_fallback(self) -> None:
        renderer = load_renderer()

        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            report = tmp_path / "2026-06-23-1015.md"
            output = tmp_path / "2026-06-23-1015-newspaper.pdf"
            report.write_text(
                """# Pavbot Aktualne Wydarzenia

Date: 2026-06-23
Status: No material change

## Gazeta

### Ogólne

#### Spokojny dzień informacyjny
Lead: Nie ma nowego faktu o wysokiej wadze publicznej.
Fakty:
- Sprawdzono oficjalne źródła. [KPRM](https://www.gov.pl/example)
Analiza: Brak materialnej zmiany jest wynikiem, nie luką w raporcie.
""",
                encoding="utf-8",
            )

            renderer.render_newspaper_pdf(
                report,
                output,
                topic_name="aktualne-wydarzenia-mobile",
            )

            with pdfplumber.open(output) as pdf:
                text = "\n".join(page.extract_text() or "" for page in pdf.pages)

        self.assertIn("Brak materialnej zmiany", text)
        self.assertIn("Technologia", text)


if __name__ == "__main__":
    unittest.main()
