from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


class ValidateMobileNewsDataTest(unittest.TestCase):
    def setUp(self) -> None:
        self.script_path = Path(__file__).resolve().parents[1] / "scripts" / "validate_mobile_news_data.py"

    def test_accepts_valid_mobile_news_data(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "valid.json"
            path.write_text(json.dumps(valid_payload(), ensure_ascii=False) + "\n", encoding="utf-8")

            result = subprocess.run(
                [sys.executable, str(self.script_path), str(path)],
                capture_output=True,
                text=True,
                check=False,
            )

            self.assertEqual(result.returncode, 0, result.stderr)

    def test_rejects_missing_tts_text_and_analysis(self) -> None:
        payload = valid_payload()
        payload["sections"][0]["articles"][0]["ttsText"] = ""
        payload["sections"][0]["articles"][0]["analysis"] = ""
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "invalid.json"
            path.write_text(json.dumps(payload, ensure_ascii=False) + "\n", encoding="utf-8")

            result = subprocess.run(
                [sys.executable, str(self.script_path), str(path)],
                capture_output=True,
                text=True,
                check=False,
            )

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("invalid mobile news data", result.stderr)
            self.assertIn("article[0].ttsText is required", result.stderr)
            self.assertIn("article[0].analysis is required", result.stderr)


def valid_payload() -> dict:
    return {
        "schemaVersion": 1,
        "topic": "aktualne-wydarzenia-mobile",
        "runDate": "2026-06-25",
        "runTime": "10:15",
        "status": "Material update",
        "headline": "Wydanie dnia",
        "leadParagraphs": ["Najważniejszy opis dnia."],
        "sections": [
            {
                "id": "polska",
                "title": "Polska",
                "summary": "Najważniejsze sygnały krajowe.",
                "articles": [
                    {
                        "id": "polska-1",
                        "section": "Polska",
                        "title": "Gdańsk jako centrum rozmów",
                        "lead": "Polska jest gospodarzem ważnych rozmów.",
                        "facts": ["KPRM zapowiedziało spotkanie."],
                        "analysis": "To łączy dyplomację, gospodarkę i bezpieczeństwo.",
                        "whyItMatters": "Użytkownik dostaje jasny sens wydarzenia.",
                        "sources": [{"title": "KPRM", "url": "https://www.gov.pl/web/premier"}],
                        "tags": ["Polska"],
                        "ttsText": "Polska jest gospodarzem ważnych rozmów. To łączy dyplomację, gospodarkę i bezpieczeństwo.",
                        "priority": "High",
                    }
                ],
            }
        ],
        "checkedSources": [{"title": "KPRM", "url": "https://www.gov.pl/web/premier"}],
        "audioArtifacts": [],
    }


if __name__ == "__main__":
    unittest.main()
