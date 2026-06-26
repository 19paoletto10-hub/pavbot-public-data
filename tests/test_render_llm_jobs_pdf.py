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
    spec = importlib.util.spec_from_file_location("render_llm_jobs_pdf", module_path)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


class RenderLlmJobsPdfTest(unittest.TestCase):
    def test_render_jobs_pdf_uses_mobile_page_and_card_tables(self) -> None:
        renderer = load_renderer()
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            markdown = tmp_path / "2026-06-25-0915.md"
            output = tmp_path / "2026-06-25-0915-llm-ai-jobs-wroclaw.pdf"
            markdown.write_text(
                """# LLM/AI Jobs Wrocław

Date: 2026-06-25 09:15 CEST
Status: Material update

## Executive Summary

New roles include agentic AI and RAG platform work.

## Top New Roles

| Company | Role | Location | Why interesting |
| --- | --- | --- | --- |
| Example AI | Senior LLM Engineer | Remote Poland | Builds RAG agents and evaluation pipelines. |

## Sources

- [Example AI role](https://example.com/jobs/senior-llm-engineer)
""",
                encoding="utf-8",
            )

            renderer.render_pdf(markdown, output)

            with pdfplumber.open(output) as pdf:
                first_page = pdf.pages[0]
                text = "\n".join(page.extract_text() or "" for page in pdf.pages)

        self.assertLessEqual(first_page.width, 430)
        self.assertGreaterEqual(first_page.height, 780)
        self.assertIn("Senior LLM Engineer", text)
        self.assertIn("Why interesting", text)
        self.assertIn("RAG agents", text)
        self.assertIn("Example AI role", text)


if __name__ == "__main__":
    unittest.main()
