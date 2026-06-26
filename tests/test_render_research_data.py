from __future__ import annotations

import importlib.util
import json
import tempfile
import unittest
from pathlib import Path


def load_module(name: str, relative_path: str):
    module_path = Path(__file__).resolve().parents[1] / relative_path
    spec = importlib.util.spec_from_file_location(name, module_path)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


class RenderResearchDataTest(unittest.TestCase):
    def test_renders_tech_news_research_data_with_analysis_fields(self) -> None:
        renderer = load_module("render_research_data", "scripts/render_research_data.py")
        validator = load_module("validate_research_data", "scripts/validate_research_data.py")

        with tempfile.TemporaryDirectory() as tmp:
            report = Path(tmp) / "research" / "tech-news" / "runs" / "2026-06-25.md"
            output = report.parents[1] / "data" / "2026-06-25-research.json"
            report.parent.mkdir(parents=True)
            report.write_text(self.tech_report(), encoding="utf-8")

            payload = renderer.render_research_data(report, output)

            self.assertTrue(output.exists())
            self.assertEqual(payload["schemaVersion"], 1)
            self.assertEqual(payload["topic"], "tech-news")
            self.assertEqual(payload["runDate"], "2026-06-25")
            self.assertEqual(payload["status"], "Material update")
            self.assertGreaterEqual(len(payload["leadParagraphs"]), 2)
            self.assertGreaterEqual(len(payload["summaryBullets"]), 1)
            self.assertEqual(payload["articles"][0]["section"], "Infrastruktura")
            self.assertIn("whatHappened", payload["articles"][0])
            self.assertIn("whyItMatters", payload["articles"][0])
            self.assertGreaterEqual(len(payload["articles"][0]["deeperAnalysis"]), 2)
            self.assertGreaterEqual(len(payload["articles"][0]["contextPoints"]), 2)
            self.assertGreaterEqual(len(payload["articles"][0]["sources"]), 1)
            self.assertFalse(validator.validate_payload(payload))

    def test_renders_polska_swiat_research_data_from_english_headings(self) -> None:
        renderer = load_module("render_research_data", "scripts/render_research_data.py")
        validator = load_module("validate_research_data", "scripts/validate_research_data.py")

        with tempfile.TemporaryDirectory() as tmp:
            report = Path(tmp) / "research" / "polska-swiat" / "runs" / "2026-06-25.md"
            output = report.parents[1] / "data" / "2026-06-25-research.json"
            report.parent.mkdir(parents=True)
            report.write_text(self.polska_report(), encoding="utf-8")

            payload = renderer.render_research_data(report, output)

            self.assertEqual(payload["topic"], "polska-swiat")
            self.assertEqual(payload["articles"][0]["section"], "Bezpieczeństwo")
            self.assertTrue(payload["articles"][0]["whyItMatters"].startswith("Ten sygnał jest ważny"))
            self.assertFalse(validator.validate_payload(payload))

    def test_validator_rejects_missing_required_analysis_fields(self) -> None:
        validator = load_module("validate_research_data", "scripts/validate_research_data.py")

        payload = json.loads(json.dumps(self.valid_payload()))
        del payload["articles"][0]["whyItMatters"]
        payload["articles"][0]["deeperAnalysis"] = []

        errors = validator.validate_payload(payload)

        self.assertIn("articles[0] missing required field: whyItMatters", errors)
        self.assertIn("articles[0].deeperAnalysis must contain at least 2 item(s)", errors)

    def valid_payload(self) -> dict:
        return {
            "schemaVersion": 1,
            "topic": "tech-news",
            "runDate": "2026-06-25",
            "runTime": None,
            "status": "Material update",
            "leadParagraphs": ["Lead"],
            "summaryBullets": ["AI: sygnał"],
            "articles": [
                {
                    "id": "tech-1",
                    "section": "AI",
                    "title": "OpenAI aktualizuje narzędzia",
                    "standfirst": "OpenAI aktualizuje narzędzia AI.",
                    "whatHappened": "OpenAI aktualizuje narzędzia AI.",
                    "whyItMatters": "To ważne dla wdrożeń AI.",
                    "deeperAnalysis": ["Analiza pierwsza.", "Analiza druga."],
                    "contextPoints": ["Co się stało: test.", "Dlaczego ważne: test."],
                    "sources": [{"title": "OpenAI", "url": "https://openai.com/news"}],
                    "priority": "High",
                    "tags": ["AI"],
                }
            ],
            "podcastTopics": [],
            "checkedSources": [{"title": "OpenAI", "url": "https://openai.com/news"}],
        }

    def tech_report(self) -> str:
        return """# Daily Research Report: tech-news
Date: 2026-06-25
Status: Material update

## Podsumowanie
AI i infrastruktura tworzą dziś najmocniejsze sygnały technologiczne.

Drugi akapit wyjaśnia, że koszty inference oraz produkty agentowe wymagają obserwacji.

## Nowe fakty
- Broadcom i OpenAI wzmacniają wątek infrastruktury AI. Źródła: [Broadcom](https://example.com/broadcom), [OpenAI](https://openai.com/news).
- Cloudflare rozwija produktowe narzędzia dla agentów i OAuth. Źródła: [Cloudflare](https://blog.cloudflare.com/news).

## Tematy do podcastu
| Priorytet | Temat | Dlaczego ważne | Źródła |
| --- | --- | --- | --- |
| High | AI infrastruktura | Koszt inference | Broadcom |

## Źródła
- [Broadcom](https://example.com/broadcom)
- [OpenAI](https://openai.com/news)
"""

    def polska_report(self) -> str:
        return """# Daily Research Report: polska-swiat
Date: 2026-06-25
Status: Material update

## Summary
Polska i świat mają dziś kilka materialnych sygnałów dotyczących bezpieczeństwa.

Drugi akapit pokazuje wpływ na decyzje publiczne i gospodarkę.

## New facts
- NATO i Polska wzmacniają komunikaty bezpieczeństwa. Source: [NATO](https://example.com/nato), [MON](https://example.com/mon).
- Energia pozostaje ryzykiem gospodarczym dla firm. Source: [Reuters](https://example.com/reuters).

## Sources
- [NATO](https://example.com/nato)
- [MON](https://example.com/mon)
"""


if __name__ == "__main__":
    unittest.main()
