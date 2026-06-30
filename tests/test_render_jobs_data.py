from __future__ import annotations

import importlib.util
import json
import tempfile
from pathlib import Path


def load_renderer():
    module_path = (
        Path(__file__).resolve().parents[1]
        / "research"
        / "llm-ai-jobs-wroclaw"
        / "tools"
        / "render_jobs_data.py"
    )
    spec = importlib.util.spec_from_file_location("render_jobs_data", module_path)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


def load_validator():
    module_path = Path(__file__).resolve().parents[1] / "scripts" / "validate_jobs_data.py"
    spec = importlib.util.spec_from_file_location("validate_jobs_data", module_path)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


def test_render_jobs_data_from_latest_polish_report() -> None:
    renderer = load_renderer()
    validator = load_validator()
    repo_root = Path(__file__).resolve().parents[1]
    markdown = repo_root / "research" / "llm-ai-jobs-wroclaw" / "runs" / "2026-06-25-0141.md"

    with tempfile.TemporaryDirectory() as tmp:
        output = Path(tmp) / "2026-06-25-0141-jobs.json"
        renderer.render_jobs_data(markdown, output)

        payload = json.loads(output.read_text(encoding="utf-8"))

    assert validator.validate_payload(payload) == []
    assert payload["runDate"] == "2026-06-25"
    assert payload["runTime"] == "01:41"
    assert payload["status"] == "Material update"
    assert "trzy materialne sygnały" in payload["executiveSummary"]
    assert payload["opportunities"][0]["company"] == "CKSource / Tiugo Technologies"
    assert payload["opportunities"][0]["workMode"] == "Remote"
    assert "38 000-45 000 PLN" in payload["opportunities"][0]["compensation"]
    assert any(item["company"] == "Accenture" for item in payload["opportunities"])
    assert len(payload["checkedSources"]) >= 5


def test_render_jobs_data_from_english_report() -> None:
    renderer = load_renderer()
    validator = load_validator()
    repo_root = Path(__file__).resolve().parents[1]
    markdown = repo_root / "research" / "llm-ai-jobs-wroclaw" / "runs" / "2026-06-24-1921.md"

    with tempfile.TemporaryDirectory() as tmp:
        output = Path(tmp) / "2026-06-24-1921-jobs.json"
        renderer.render_jobs_data(markdown, output)

        payload = json.loads(output.read_text(encoding="utf-8"))

    assert validator.validate_payload(payload) == []
    assert payload["runDate"] == "2026-06-24"
    assert payload["runTime"] == "19:21"
    assert "EPAM" in payload["opportunities"][0]["company"]
    assert payload["opportunities"][0]["workMode"] == "Remote"
    assert payload["opportunities"][0]["sourceURLs"]
    assert any("ACAISOFT" in item["company"] for item in payload["opportunities"])


def test_render_jobs_data_accepts_spaced_location_remote_label() -> None:
    renderer = load_renderer()

    markdown = """# LLM/AI jobs Wrocław

Date: 2026-06-27 01:41 Europe/Warsaw
Status: Material update

## Executive Summary
Krótki testowy raport.

## Top New Or Materially Changed Roles

### 1. TestCo - Senior LLM Engineer
- Lokalizacja / remote: `Cała Polska (praca zdalna)`
- Fit LLM/AI: Budowa systemów RAG i agentów.
- Dlaczego interesujące: Hands-on GenAI.
- Niepewność: Brak widełek.
- Wynagrodzenie: Brak publicznych widełek.
- Źródła: [ogłoszenie](https://example.com/jobs/senior-llm-engineer)

## Scope Checked
- [Example jobs](https://example.com/jobs) - checked.
"""

    payload = renderer.parse_report(markdown)

    assert payload["opportunities"][0]["location"] == "Cała Polska (praca zdalna)"
    assert payload["opportunities"][0]["workMode"] == "Remote"


def test_render_jobs_data_supports_top_roles_with_flat_link_bullets() -> None:
    renderer = load_renderer()
    validator = load_validator()

    markdown = """# LLM/AI Jobs Wrocław

Date: 2026-06-29 01:41 Europe/Warsaw
Status: Material update

## Zakres sprawdzony

- [Just Join IT](https://justjoin.it/jobs) - checked

## Podsumowanie zarządcze

Nowy pakiet ról AI dla Polski z naciskiem na GenAI i agentów.

## Top Roles

- [Primotly - Senior AI Engineer (Python, GenAI, GCP)](https://example.com/primotly): `Wrocław +4, remote`; budowa agentów i workflow GenAI na GCP; `29 000-36 500 PLN net/mies. B2B`; niepewność niska.
- [Remodevs - Senior AI Engineer](https://example.com/remodevs): `Cała Polska, praca zdalna`; agent workflows, evals i tracing dla systemów LLM; `33 970-42 462 PLN net/mies. B2B`; niepewność średnia.

## Zmiany od poprzedniej rundy

- Doszły dwa nowe publiczne ogłoszenia.

## Rekomendowane akcje

- Sprawdzić kolejne aktualizacje widełek.
"""

    payload = renderer.parse_report(markdown)

    assert validator.validate_payload(payload) == []
    assert payload["opportunities"][0]["company"] == "Primotly"
    assert payload["opportunities"][0]["title"] == "Senior AI Engineer (Python, GenAI, GCP)"
    assert payload["opportunities"][0]["location"] == "Wrocław +4, remote"
    assert payload["opportunities"][0]["workMode"] == "Remote"
    assert payload["opportunities"][0]["compensation"] == "29 000-36 500 PLN net/mies. B2B"
    assert payload["opportunities"][0]["sourceURLs"] == ["https://example.com/primotly"]
    assert payload["opportunities"][1]["company"] == "Remodevs"
