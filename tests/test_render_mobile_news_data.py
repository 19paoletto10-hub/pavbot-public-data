from __future__ import annotations

import importlib.util
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


class RenderMobileNewsDataTest(unittest.TestCase):
    def test_renders_valid_mobile_news_data_from_gazeta_report(self) -> None:
        renderer = load_module("render_mobile_news_data", "scripts/render_mobile_news_data.py")
        validator = load_module("validate_mobile_news_data", "scripts/validate_mobile_news_data.py")

        with tempfile.TemporaryDirectory() as tmp:
            report = Path(tmp) / "research" / "aktualne-wydarzenia-mobile" / "runs" / "2026-07-08-1935.md"
            output = report.parents[1] / "data" / "2026-07-08-1935-mobile-news.json"
            report.parent.mkdir(parents=True)
            report.write_text(self.report_markdown(), encoding="utf-8")
            audio_file = (
                report.parents[1]
                / "podcasts"
                / "2026-07-08-1935"
                / "audio"
                / "female-piper"
                / "podcast.mp3"
            )
            audio_file.parent.mkdir(parents=True)
            audio_file.write_bytes(b"mp3")
            (report.parents[1] / "podcasts" / "2026-07-08-1935" / "tts_variants.json").write_text(
                """{
                  "variants": [
                    {
                      "id": "female-piper",
                      "engine": "piper",
                      "voice": "pl_PL-gosia-medium",
                      "status": "ok",
                      "duration_seconds": 387.1,
                      "output_file": "research/aktualne-wydarzenia-mobile/podcasts/2026-07-08-1935/audio/female-piper/podcast.mp3",
                      "render_json": "research/aktualne-wydarzenia-mobile/podcasts/2026-07-08-1935/audio/female-piper/render.json",
                      "error": null
                    },
                    {
                      "id": "male-xtts",
                      "status": "failed",
                      "output_file": null,
                      "error": "render failed"
                    }
                  ]
                }""",
                encoding="utf-8",
            )

            payload = renderer.render_mobile_news_data(report, output)

            self.assertTrue(output.exists())
            self.assertEqual(payload["schemaVersion"], 1)
            self.assertEqual(payload["topic"], "aktualne-wydarzenia-mobile")
            self.assertEqual(payload["runDate"], "2026-07-08")
            self.assertEqual(payload["runTime"], "19:35")
            self.assertEqual(payload["headline"], "Wieczorny brief ma komplet danych.")
            self.assertEqual([section["title"] for section in payload["sections"]], renderer.REQUIRED_SECTION_TITLES)
            self.assertEqual(payload["sections"][0]["articles"][0]["title"], "Pierwszy sygnal")
            self.assertEqual(payload["sections"][0]["articles"][0]["sources"][0]["title"], "RCB")
            self.assertEqual(
                payload["audioArtifacts"],
                [
                    {
                        "variant": "female-piper",
                        "path": "research/aktualne-wydarzenia-mobile/podcasts/2026-07-08-1935/audio/female-piper/podcast.mp3",
                    }
                ],
            )
            self.assertFalse(validator.validate_payload(payload))

    def test_validator_rejects_payload_without_audio_artifacts(self) -> None:
        validator = load_module("validate_mobile_news_data", "scripts/validate_mobile_news_data.py")
        payload = self.valid_payload()
        payload.pop("audioArtifacts")

        errors = validator.validate_payload(payload)

        self.assertIn("missing required field: audioArtifacts", errors)

    def test_validator_rejects_payload_with_empty_audio_artifacts(self) -> None:
        validator = load_module("validate_mobile_news_data", "scripts/validate_mobile_news_data.py")
        payload = self.valid_payload()
        payload["audioArtifacts"] = []

        errors = validator.validate_payload(payload)

        self.assertIn("audioArtifacts must contain at least one item", errors)

    def report_markdown(self) -> str:
        sections = "\n\n".join(
            self.section_markdown(title, index)
            for index, title in enumerate(["Ogólne", "Polska", "Polityka", "Sprawy zagraniczne", "Technologia"], start=1)
        )
        return f"""# Pavbot Aktualne Wydarzenia Mobile

Date: 2026-07-08
Created: 2026-07-08 19:35 CEST
Status: Material update

## Zakres sprawdzonych źródeł

- [RCB](https://example.com/rcb)
- [NATO](https://example.com/nato)

## Podsumowanie

- Wieczorny brief ma komplet danych.
- Drugi akapit pilnuje kontekstu publikacji.

## Gazeta

{sections}
"""

    def section_markdown(self, title: str, index: int) -> str:
        first_title = "Pierwszy sygnal" if index == 1 else f"{title} sygnal pierwszy"
        return f"""### {title}

Wprowadzenie: Sekcja {title} ma wprowadzenie inne niz lead artykulu.

#### {first_title}

Lead: Lead pierwszy dla sekcji {title}.
Fakty:
- Fakt pierwszy dla sekcji {title}. [RCB](https://example.com/rcb)
- Fakt drugi dla sekcji {title}. [NATO](https://example.com/nato)
Analiza: Analiza pierwszego artykulu w sekcji {title}.
Dlaczego to ważne: Znaczenie pierwszego artykulu w sekcji {title}.

#### {title} sygnal drugi

Lead: Lead drugi dla sekcji {title}.
Fakty:
- Kolejny fakt dla sekcji {title}. [RCB](https://example.com/rcb)
Analiza: Analiza drugiego artykulu w sekcji {title}.
Dlaczego to ważne: Znaczenie drugiego artykulu w sekcji {title}.
"""

    def valid_payload(self) -> dict:
        sections = []
        for title in ["Ogólne", "Polska", "Polityka", "Sprawy zagraniczne", "Technologia"]:
            sections.append(
                {
                    "id": title.lower().replace(" ", "-"),
                    "title": title,
                    "summary": f"Podsumowanie {title}",
                    "articles": [
                        self.article(title, 1),
                        self.article(title, 2),
                    ],
                }
            )
        return {
            "schemaVersion": 1,
            "topic": "aktualne-wydarzenia-mobile",
            "runDate": "2026-07-08",
            "runTime": "19:35",
            "status": "Material update",
            "headline": "Wydanie dnia",
            "leadParagraphs": ["Najważniejsze wydarzenia dnia."],
            "checkedSources": [{"title": "RCB", "url": "https://example.com/rcb"}],
            "sections": sections,
            "audioArtifacts": [
                {
                    "variant": "female-piper",
                    "path": "research/aktualne-wydarzenia-mobile/podcasts/2026-07-08-1935/audio/female-piper/podcast.mp3",
                }
            ],
        }

    def article(self, section: str, index: int) -> dict:
        return {
            "id": f"{section}-{index}",
            "section": section,
            "title": f"{section} artykuł {index}",
            "lead": f"Lead {index}",
            "facts": [f"Fakt {index}"],
            "analysis": f"Analiza {index}",
            "whyItMatters": f"Znaczenie {index}",
            "sources": [{"title": "RCB", "url": "https://example.com/rcb"}],
            "tags": [section],
            "ttsText": f"Tekst TTS {index}",
            "priority": "High",
        }


if __name__ == "__main__":
    unittest.main()
