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
        / "llm-ai-jobs-wroclaw"
        / "tools"
        / "render_report_pdf.py"
    )
    spec = importlib.util.spec_from_file_location("llm_ai_jobs_render_report_pdf", module_path)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


class LlmAiJobsRenderReportPdfTest(unittest.TestCase):
    def test_topic_local_pdf_wrapper_renders_mobile_pdf(self) -> None:
        renderer = load_renderer()
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            markdown = tmp_path / "2026-07-09-1740.md"
            output = tmp_path / "2026-07-09-1740-llm-ai-jobs-wroclaw.pdf"
            markdown.write_text(
                """# Daily Research Report: llm-ai-jobs-wroclaw

Date: 2026-07-09 17:40 CEST
Status: Material update

## Summary

Nowy testowy raport dla automatyzacji ofert pracy.

## Top New Or Materially Changed Roles

### 1. TestCo - Senior LLM Engineer
- Lokalizacja / remote: Wrocław / hybrid
- Fit LLM/AI: Budowa systemów RAG i ocena modeli.
- Dlaczego interesujące: Hands-on rola blisko produkcji.
- Niepewność: Brak publicznych widełek.
- Wynagrodzenie: Brak publicznych widełek.
- Źródła: [Oferta](https://example.com/jobs/testco-senior-llm-engineer)

## Sources

- [Oferta](https://example.com/jobs/testco-senior-llm-engineer)
""",
                encoding="utf-8",
            )

            renderer.render_pdf(markdown, output, topic_name="llm-ai-jobs-wroclaw")

            self.assertTrue(output.exists())
            self.assertGreater(output.stat().st_size, 10_000)
            with pdfplumber.open(output) as pdf:
                text = "\n".join(page.extract_text() or "" for page in pdf.pages)
                self.assertLessEqual(pdf.pages[0].width, 430)
                self.assertGreaterEqual(pdf.pages[0].height, 780)

        self.assertIn("Daily Research Report: llm-ai-jobs-wroclaw", text)
        self.assertIn("Senior LLM Engineer", text)


if __name__ == "__main__":
    unittest.main()
