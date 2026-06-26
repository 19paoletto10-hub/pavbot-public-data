from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

import pdfplumber


class RenderPodcastBriefPdfTest(unittest.TestCase):
    def test_render_podcast_brief_uses_mobile_page_and_preserves_metadata_sources(self) -> None:
        repo_root = Path(__file__).resolve().parents[1]
        renderer = repo_root / ".agents" / "scripts" / "podcast" / "render-podcast-brief-pdf.py"
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            podcast_dir = tmp_path / "research" / "tech-news" / "podcasts" / "2026-06-25"
            podcast_dir.mkdir(parents=True)
            output = podcast_dir / "brief.pdf"
            (podcast_dir / "script.md").write_text(
                """# Pavbot Tech News

Pierwszy temat to nowy model agentowy. Wyjaśniamy, dlaczego to ważne dla firm i programistów.

Drugi temat dotyczy bezpieczeństwa AI. Krótko oddzielamy fakty od marketingu.
""",
                encoding="utf-8",
            )
            (podcast_dir / "sources.md").write_text(
                """## Źródła użyte w scenariuszu

- [OpenAI](https://openai.com/example)
- [NCSC](https://www.ncsc.gov.uk/example)
""",
                encoding="utf-8",
            )
            (podcast_dir / "render.json").write_text(
                json.dumps(
                    {
                        "duration_seconds": 462,
                        "word_count": 980,
                        "engine_used": "piper",
                        "model": "pl_PL-gosia-medium",
                    }
                ),
                encoding="utf-8",
            )

            subprocess.run([sys.executable, str(renderer), str(podcast_dir), str(output)], check=True)

            with pdfplumber.open(output) as pdf:
                first_page = pdf.pages[0]
                text = "\n".join(page.extract_text() or "" for page in pdf.pages)

        self.assertLessEqual(first_page.width, 430)
        self.assertGreaterEqual(first_page.height, 780)
        self.assertIn("Pavbot Podcast Brief", text)
        self.assertIn("7:42", text)
        self.assertIn("piper", text)
        self.assertIn("OpenAI", text)


if __name__ == "__main__":
    unittest.main()
