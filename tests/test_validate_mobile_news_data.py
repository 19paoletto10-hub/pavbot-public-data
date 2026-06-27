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

    def test_rejects_section_with_single_article(self) -> None:
        payload = valid_payload()
        payload["sections"][0]["articles"] = payload["sections"][0]["articles"][:1]
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
            self.assertIn("sections[0].articles must contain at least 2 item(s)", result.stderr)

    def test_rejects_summary_that_duplicates_article_lead(self) -> None:
        payload = valid_payload()
        payload["sections"][0]["summary"] = payload["sections"][0]["articles"][0]["lead"]
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
            self.assertIn("sections[0].summary must not duplicate article lead", result.stderr)


def valid_payload() -> dict:
    sections = []
    for section in ["Ogólne", "Polska", "Polityka", "Sprawy zagraniczne", "Technologia"]:
        slug = {
            "Ogólne": "ogolne",
            "Polska": "polska",
            "Polityka": "polityka",
            "Sprawy zagraniczne": "sprawy-zagraniczne",
            "Technologia": "technologia",
        }[section]
        sections.append(
            {
                "id": slug,
                "title": section,
                "summary": f"{section}: syntetyczny opis stanu informacji bez kopiowania leadu artykułu.",
                "articles": [
                    article_payload(slug, section, 1),
                    article_payload(slug, section, 2),
                ],
            }
        )
    return {
        "schemaVersion": 1,
        "topic": "aktualne-wydarzenia-mobile",
        "runDate": "2026-06-25",
        "runTime": "10:15",
        "status": "Material update",
        "headline": "Wydanie dnia",
        "leadParagraphs": ["Najważniejszy opis dnia."],
        "sections": sections,
        "checkedSources": [{"title": "KPRM", "url": "https://www.gov.pl/web/premier"}],
        "audioArtifacts": [],
    }


def article_payload(slug: str, section: str, index: int) -> dict:
    return {
        "id": f"{slug}-{index}",
        "section": section,
        "title": f"{section}: temat {index}",
        "lead": f"{section} ma osobny lead artykułu numer {index}.",
        "facts": [f"Potwierdzony fakt {index} dla sekcji {section}."],
        "analysis": f"Analiza numer {index} porządkuje znaczenie tematu w sekcji {section}.",
        "whyItMatters": "Użytkownik dostaje jasny sens wydarzenia.",
        "sources": [{"title": "KPRM", "url": f"https://www.gov.pl/web/premier?test={slug}-{index}"}],
        "tags": [section],
        "ttsText": f"{section}: temat {index}. {section} ma osobny lead artykułu numer {index}.",
        "priority": "High" if index == 1 else "Medium",
    }


if __name__ == "__main__":
    unittest.main()
