from __future__ import annotations

import importlib.util
import json
from pathlib import Path


def load_validator():
    module_path = (
        Path(__file__).resolve().parents[1]
        / "scripts"
        / "validate_jobs_data.py"
    )
    spec = importlib.util.spec_from_file_location("validate_jobs_data", module_path)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


def valid_payload() -> dict:
    return {
        "schemaVersion": 1,
        "status": "Material update",
        "runDate": "2026-06-25",
        "runTime": "01:41",
        "executiveSummary": "Runda przyniosła nowe role LLM/AI.",
        "opportunities": [
            {
                "rank": 1,
                "title": "Principal AI Engineer",
                "company": "CKSource",
                "location": "Remote Poland",
                "workMode": "Remote",
                "compensation": "38 000-45 000 PLN",
                "seniority": "Principal",
                "fitSummary": "Agentic workflows i AI-assisted engineering.",
                "whyInteresting": "Silny praktyczny fit do systemów LLM.",
                "uncertainty": "Tytuł różni się między hubem i kartą.",
                "sourceURLs": ["https://example.com/job"],
                "tags": ["LLM", "Agentic AI"],
            }
        ],
        "changes": ["Nowa oficjalna rola"],
        "risks": ["Drift tytułu"],
        "recommendedActions": ["Sprawdzić status w kolejnej rundzie"],
        "checkedSources": [{"title": "CKSource careers", "url": "https://example.com"}],
    }


def test_validate_jobs_data_accepts_valid_payload(tmp_path: Path) -> None:
    validator = load_validator()
    path = tmp_path / "2026-06-25-0141-jobs.json"
    path.write_text(json.dumps(valid_payload(), ensure_ascii=False), encoding="utf-8")

    errors = validator.validate_file(path)

    assert errors == []


def test_validate_jobs_data_rejects_missing_required_fields(tmp_path: Path) -> None:
    validator = load_validator()
    path = tmp_path / "2026-06-25-0141-jobs.json"
    payload = valid_payload()
    del payload["status"]
    payload["opportunities"][0]["sourceURLs"] = []
    path.write_text(json.dumps(payload, ensure_ascii=False), encoding="utf-8")

    errors = validator.validate_file(path)

    assert "missing required field: status" in errors
    assert "opportunities[0].sourceURLs must contain at least one URL" in errors
