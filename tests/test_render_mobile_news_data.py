from __future__ import annotations

import importlib.util
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


def load_renderer():
    module_path = Path(__file__).resolve().parents[1] / "scripts" / "render_mobile_news_data.py"
    spec = importlib.util.spec_from_file_location("render_mobile_news_data", module_path)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


class RenderMobileNewsDataTest(unittest.TestCase):
    def test_renders_structured_mobile_news_data_from_gazeta_section(self) -> None:
        renderer = load_renderer()

        report = """
# Mobile News Brief: aktualne-wydarzenia-mobile

Date: 2026-06-25 10:15 CEST
Status: Material update

## Summary
Poranny przegląd wskazuje, że Polska i bezpieczeństwo są głównymi osiami dnia.

## Gazeta

### Polska

#### Gdańsk jako centrum rozmów o Ukrainie
Lead: Polska przejmuje dziś rolę gospodarza rozmów o odbudowie Ukrainy.
Fakty:
- KPRM zapowiada udział premiera w konferencji. Źródło: [KPRM](https://www.gov.pl/web/premier)
- Komisja Europejska opisuje priorytety odbudowy. Źródło: [KE](https://commission.europa.eu)
Analiza: To sygnał, że dyplomacja, gospodarka i bezpieczeństwo są dziś połączone.
Dlaczego ważne: Użytkownik dostaje jasny kontekst, czy temat jest tylko ceremonialny, czy operacyjny.

### Technologia

#### Brak materialnej zmiany
Lead: W sprawach technologicznych nie znaleziono dziś silnego nowego sygnału.
Fakty:
- Sprawdzono oficjalne źródła i redakcje technologiczne.
Analiza: Brak nowego faktu też jest informacją, bo ogranicza szum.
"""

        payload = renderer.build_mobile_news_payload(
            markdown=report,
            source_path=Path("research/aktualne-wydarzenia-mobile/runs/2026-06-25-1015.md"),
        )

        self.assertEqual(payload["schemaVersion"], 1)
        self.assertEqual(payload["topic"], "aktualne-wydarzenia-mobile")
        self.assertEqual(payload["runDate"], "2026-06-25")
        self.assertEqual(payload["runTime"], "10:15")
        self.assertEqual(payload["status"], "Material update")
        self.assertIn("Poranny przegląd", payload["leadParagraphs"][0])
        self.assertEqual([section["title"] for section in payload["sections"]], ["Polska", "Technologia"])
        article = payload["sections"][0]["articles"][0]
        self.assertEqual(article["title"], "Gdańsk jako centrum rozmów o Ukrainie")
        self.assertGreaterEqual(len(article["facts"]), 2)
        self.assertEqual(article["sources"][0]["title"], "KPRM")
        self.assertNotIn("https://", article["ttsText"])
        self.assertIn("Polska przejmuje dziś rolę gospodarza", article["ttsText"])

    def test_falls_back_to_new_facts_when_gazeta_section_is_missing(self) -> None:
        renderer = load_renderer()

        report = """
# Mobile News Brief: aktualne-wydarzenia-mobile

Date: 2026-06-25
Status: Material update

## Summary
Najważniejszy sygnał dotyczy bezpieczeństwa i pogody.

## Nowe fakty

- RCB informuje o fali upałów i alertach dla mieszkańców. Źródło: [RCB](https://www.gov.pl/web/rcb)
- NATO potwierdza rozmowy o wsparciu Ukrainy. Źródło: [NATO](https://www.nato.int)
"""

        payload = renderer.build_mobile_news_payload(
            markdown=report,
            source_path=Path("research/aktualne-wydarzenia-mobile/runs/2026-06-25.md"),
        )

        self.assertEqual(payload["runDate"], "2026-06-25")
        self.assertIsNone(payload["runTime"])
        self.assertGreaterEqual(sum(len(section["articles"]) for section in payload["sections"]), 2)
        self.assertTrue(any(article["sources"] for section in payload["sections"] for article in section["articles"]))

    def test_cli_writes_json_output(self) -> None:
        script_path = Path(__file__).resolve().parents[1] / "scripts" / "render_mobile_news_data.py"
        with tempfile.TemporaryDirectory() as tmp:
            source = Path(tmp) / "2026-06-25-1015.md"
            output = Path(tmp) / "2026-06-25-1015-mobile-news.json"
            source.write_text(
                """
# Mobile News Brief
Date: 2026-06-25 10:15 CEST
Status: Material update

## Summary
Lead dnia.

## Gazeta
### Ogólne
#### Testowy artykuł
Lead: To jest lead.
Fakty:
- Fakt ze źródłem. Źródło: [Źródło](https://example.com)
Analiza: To jest analiza.
""",
                encoding="utf-8",
            )

            result = subprocess.run(
                [sys.executable, str(script_path), str(source), str(output)],
                capture_output=True,
                text=True,
                check=False,
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            data = json.loads(output.read_text(encoding="utf-8"))
            self.assertEqual(data["sections"][0]["articles"][0]["title"], "Testowy artykuł")


if __name__ == "__main__":
    unittest.main()
