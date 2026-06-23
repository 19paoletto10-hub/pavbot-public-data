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
        / "render_mobile_brief_pdf.py"
    )
    spec = importlib.util.spec_from_file_location("render_mobile_brief_pdf", module_path)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


class RenderMobileBriefPdfTest(unittest.TestCase):
    def test_render_mobile_pdf_contains_news_sources_and_tts_metadata(self) -> None:
        renderer = load_renderer()

        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            report = tmp_path / "2026-06-23.md"
            podcast_dir = tmp_path / "podcasts" / "2026-06-23"
            output = tmp_path / "2026-06-23-mobile-brief.pdf"
            podcast_dir.mkdir(parents=True)
            report.write_text(
                """# Mobile News Brief: aktualne-wydarzenia-mobile

Date: 2026-06-23
Status: Material update

## Nowe fakty

- Rząd opublikował nowy komunikat o bezpieczeństwie. [KPRM](https://www.gov.pl/example)
- BBC potwierdza międzynarodowy kontekst wydarzenia. [BBC](https://www.bbc.com/example)

## Interpretacja

- To ważny sygnał dla odbiorców w Polsce, choć bez paniki: kawa stygnie, fakty zostają.

## Źródła

- [KPRM](https://www.gov.pl/example)
- [BBC](https://www.bbc.com/example)
""",
                encoding="utf-8",
            )
            (podcast_dir / "script.md").write_text(
                "# Scenariusz\n\nDzień dobry. Oto krótki przegląd wydarzeń po polsku.\n",
                encoding="utf-8",
            )
            (podcast_dir / "sources.md").write_text(
                "## Źródła użyte w scenariuszu\n\n- [KPRM](https://www.gov.pl/example)\n",
                encoding="utf-8",
            )
            (podcast_dir / "tts_variants.json").write_text(
                """{
  "language": "pl",
  "speed": 1.1,
  "variants": [
    {"id": "female-piper", "engine": "piper", "voice": "pl_PL-gosia-medium"},
    {"id": "male-xtts", "engine": "xtts", "voice": "Andrew Chipper"}
  ]
}
""",
                encoding="utf-8",
            )

            renderer.render_mobile_pdf(
                report,
                podcast_dir,
                output,
                topic_name="aktualne-wydarzenia-mobile",
            )

            self.assertTrue(output.exists())
            self.assertGreater(output.stat().st_size, 10_000)
            with pdfplumber.open(output) as pdf:
                text = "\n".join(page.extract_text() or "" for page in pdf.pages)

        self.assertIn("Mobile News Brief", text)
        self.assertIn("Nowe fakty", text)
        self.assertIn("Interpretacja", text)
        self.assertIn("KPRM", text)
        self.assertIn("Język TTS: pl", text)
        self.assertIn("female-piper", text)
        self.assertIn("male-xtts", text)


if __name__ == "__main__":
    unittest.main()
