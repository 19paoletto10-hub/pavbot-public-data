from __future__ import annotations

import importlib.util
import tempfile
import unittest
from pathlib import Path

import pdfplumber


def load_renderer():
    module_path = Path(__file__).resolve().parents[1] / "scripts" / "render_research_pdf.py"
    spec = importlib.util.spec_from_file_location("render_research_pdf", module_path)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


class RenderResearchPdfTest(unittest.TestCase):
    def test_render_research_pdf_preserves_polish_report_content(self) -> None:
        renderer = load_renderer()
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            markdown = tmp_path / "2026-06-18.md"
            output = tmp_path / "2026-06-18-tech-news.pdf"
            markdown.write_text(
                """# Daily Research Report: tech-news

Date: 2026-06-18
Status: Material update

## Podsumowanie

Najważniejszy temat dnia: regulacja AI i cyberbezpieczeństwo.

## Tematy do podcastu

| Priorytet | Tytuł | Dlaczego to ważne | Główne źródła |
| --- | --- | --- | --- |
| High | G7 i frontier AI | Państwa realnie kontrolują dostęp do modeli. | AP; Axios |

## Źródła

- [AP News](https://apnews.com/example)
""",
                encoding="utf-8",
            )

            renderer.render_pdf(markdown, output, topic_name="tech-news")

            self.assertTrue(output.exists())
            self.assertGreater(output.stat().st_size, 10_000)
            with pdfplumber.open(output) as pdf:
                text = "\n".join(page.extract_text() or "" for page in pdf.pages)

        self.assertIn("Daily Research Report: tech-news", text)
        self.assertIn("Najważniejszy temat dnia", text)
        self.assertIn("G7 i frontier AI", text)
        self.assertIn("Źródła", text)

    def test_render_research_pdf_uses_mobile_page_and_highlight_cards(self) -> None:
        renderer = load_renderer()
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            markdown = tmp_path / "2026-06-24.md"
            output = tmp_path / "2026-06-24-polska-swiat.pdf"
            markdown.write_text(
                """# Daily Research Report: polska-swiat

Date: 2026-06-24
Status: Material update

## Podsumowanie

Najważniejszy temat dnia: decyzje polityczne i bezpieczeństwo publiczne.

## Tematy do podcastu

| Priorytet | Tytuł | Dlaczego to ważne | Główne źródła |
| --- | --- | --- | --- |
| High | Nowy pakiet ustaw | Wpływa na codzienne decyzje obywateli i firm. | [PAP](https://example.com/pap); [BBC](https://example.com/bbc) |
| Medium | Europejska debata | Zmienia kontekst spraw zagranicznych. | Reuters |

## Źródła

- [PAP](https://example.com/pap)
""",
                encoding="utf-8",
            )

            renderer.render_pdf(markdown, output, topic_name="polska-swiat")

            with pdfplumber.open(output) as pdf:
                first_page = pdf.pages[0]
                text = "\n".join(page.extract_text() or "" for page in pdf.pages)

        self.assertLessEqual(first_page.width, 430)
        self.assertGreaterEqual(first_page.height, 780)
        self.assertIn("NAJWAŻNIEJSZE", text)
        self.assertIn("Dlaczego to ważne", text)
        self.assertIn("Wpływa na codzienne decyzje", text)
        self.assertIn("PAP", text)

    def test_render_research_pdf_merges_wrapped_bullets_and_skips_duplicate_metadata(self) -> None:
        renderer = load_renderer()
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            markdown = tmp_path / "2026-06-25.md"
            output = tmp_path / "2026-06-25-tech-news.pdf"
            markdown.write_text(
                """# Daily Research Report: tech-news

Date: 2026-06-25
Status: Material update

## Scope Checked

- First source group wraps
  onto a second physical Markdown line without becoming a new paragraph.
- Second source group stays separate.

## Summary

The briefing should keep metadata in the header only.

## Sources

- [Example](https://example.com/source)
""",
                encoding="utf-8",
            )

            renderer.render_pdf(markdown, output, topic_name="tech-news")

            with pdfplumber.open(output) as pdf:
                text = "\n".join(page.extract_text() or "" for page in pdf.pages)

        normalized = " ".join(text.split())
        self.assertIn("First source group wraps onto a second physical Markdown line", normalized)
        self.assertIn(
            "without becoming a new paragraph. - Second source group stays separate.",
            normalized,
        )
        self.assertEqual(text.count("Date: 2026-06-25"), 1)
        self.assertEqual(text.count("Status: Material update"), 1)


if __name__ == "__main__":
    unittest.main()
