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
