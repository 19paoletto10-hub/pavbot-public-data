from __future__ import annotations

import json
import subprocess
import sys
import tempfile
from pathlib import Path


SCRIPT = Path(__file__).resolve().parents[1] / "scripts" / "pavbot_preflight_source_check.py"


def run_preflight(*args: str) -> dict:
    result = subprocess.run(
        [sys.executable, str(SCRIPT), *args],
        capture_output=True,
        text=True,
        check=False,
    )
    assert result.returncode == 0, result.stderr
    return json.loads(result.stdout)


def test_preflight_tracks_hash_changes_and_unchanged_sources() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        source = root / "source.txt"
        state = root / "state.json"
        topic = root / "research" / "topic"
        topic.mkdir(parents=True)
        source.write_text("alpha\n", encoding="utf-8")

        first = run_preflight(
            str(topic),
            "--automation-id",
            "test-automation",
            "--source",
            f"local={source}",
            "--state-file",
            str(state),
            "--update-state",
        )
        assert first["materialChangeHint"] == "unknown"
        assert first["reason"] == "no_previous_state"

        unchanged = run_preflight(
            str(topic),
            "--automation-id",
            "test-automation",
            "--source",
            f"local={source}",
            "--state-file",
            str(state),
        )
        assert unchanged["materialChangeHint"] == "no"
        assert unchanged["sources"][0]["changed"] is False

        source.write_text("beta\n", encoding="utf-8")
        changed = run_preflight(
            str(topic),
            "--automation-id",
            "test-automation",
            "--source",
            f"local={source}",
            "--state-file",
            str(state),
        )
        assert changed["materialChangeHint"] == "yes"
        assert changed["sources"][0]["changed"] is True


def test_preflight_unknown_for_unreachable_source() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        missing = root / "missing.txt"
        state = root / "state.json"
        topic = root / "research" / "topic"
        topic.mkdir(parents=True)

        result = run_preflight(
            str(topic),
            "--automation-id",
            "test-automation",
            "--source",
            f"missing={missing}",
            "--state-file",
            str(state),
        )

        assert result["materialChangeHint"] == "unknown"
        assert result["sources"][0]["status"] == "unreachable"
