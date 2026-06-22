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


if __name__ == "__main__":
    unittest.main()
