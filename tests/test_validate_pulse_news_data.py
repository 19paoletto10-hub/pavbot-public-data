from __future__ import annotations

import importlib.util
from pathlib import Path


def load_validator():
    module_path = (
        Path(__file__).resolve().parents[1]
        / "scripts"
        / "validate_pulse_news_data.py"
    )
    spec = importlib.util.spec_from_file_location("validate_pulse_news_data", module_path)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


def valid_payload(item_count: int = 12) -> dict:
    sections = [
        "Polska",
        "Świat",
        "Polityka",
        "Bezpieczeństwo",
        "Gospodarka",
        "Technologia",
        "Alerty",
        "Polska",
        "Świat",
        "Gospodarka",
        "Technologia",
        "Bezpieczeństwo",
    ]
    items = []
    for index, section in enumerate(sections[:item_count], start=1):
        items.append(
            {
                "id": f"pulse-{index}",
                "section": section,
                "title": f"Temat dnia {index}",
                "lead": f"Krótki opis tematu {index}.",
                "whatHappened": f"Co się stało w temacie {index}.",
                "keyFacts": [f"Fakt {index}.", f"Drugi fakt {index}."],
                "reactions": [f"Reakcja {index}."],
                "whyItMatters": f"Dlaczego temat {index} jest ważny.",
                "context": f"Kontekst tematu {index}.",
                "watchNext": [f"Obserwuj temat {index}."],
                "sources": [{"title": "TVN24", "url": f"https://example.com/{index}"}],
                "tags": [section, "Puls dnia"],
                "priority": "High" if index <= 4 else "Medium",
            }
        )
    return {
        "schemaVersion": 1,
        "topic": "puls-dnia-news",
        "runDate": "2026-06-26",
        "runTime": "12:00",
        "status": "Material update",
        "headline": "Puls dnia",
        "summary": "Najważniejsze tematy z ostatnich trzech godzin.",
        "items": items,
        "checkedSources": [{"title": "TVN24", "url": "https://www.tvn24.pl"}],
    }


def test_valid_pulse_news_payload_passes() -> None:
    validator = load_validator()

    assert validator.validate_payload(valid_payload()) == []


def test_rejects_less_than_twelve_items() -> None:
    validator = load_validator()

    errors = validator.validate_payload(valid_payload(item_count=10))

    assert "items must contain at least 12 items" in errors


def test_rejects_odd_number_of_items() -> None:
    validator = load_validator()

    errors = validator.validate_payload(valid_payload(item_count=11))

    assert "items count must be even so iOS can render paired cards" in errors


def test_rejects_item_without_sources_and_analysis() -> None:
    validator = load_validator()
    payload = valid_payload()
    payload["items"][0]["sources"] = []
    payload["items"][0]["whyItMatters"] = ""

    errors = validator.validate_payload(payload)

    assert "items[0].sources must contain at least one item" in errors
    assert "items[0].whyItMatters must be a non-empty string" in errors
