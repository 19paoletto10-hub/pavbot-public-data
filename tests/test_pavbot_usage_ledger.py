from __future__ import annotations

import json
import sqlite3
import subprocess
import sys
import tempfile
from pathlib import Path


SCRIPT = Path(__file__).resolve().parents[1] / "scripts" / "pavbot_usage_ledger.py"


def run_ledger(*args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, str(SCRIPT), *args],
        capture_output=True,
        text=True,
        check=False,
    )


def test_usage_ledger_creates_and_finishes_private_run() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        db = Path(tmp) / "usage-ledger.sqlite3"

        started = run_ledger(
            "--db",
            str(db),
            "start",
            "--automation-id",
            "pavbot-test",
            "--topic",
            "research/test",
            "--model",
            "gpt-test",
            "--preflight-result",
            '{"materialChangeHint":"no"}',
        )
        assert started.returncode == 0, started.stderr
        run_id = json.loads(started.stdout)["runId"]

        finished = run_ledger(
            "--db",
            str(db),
            "finish",
            "--run-id",
            run_id,
            "--status",
            "failed",
            "--input-tokens",
            "10",
            "--cached-tokens",
            "3",
            "--output-tokens",
            "5",
            "--reasoning-tokens",
            "2",
            "--web-calls",
            "4",
            "--tool-calls",
            "7",
            "--publish-status",
            "partial",
            "--remote-verification-status",
            "failed",
            "--error-message",
            "Authorization: Bearer super-secret-token",
        )
        assert finished.returncode == 0, finished.stderr

        conn = sqlite3.connect(db)
        row = conn.execute(
            """
            select automation_id, topic, status, model, input_tokens, cached_tokens,
                   output_tokens, reasoning_tokens, web_calls, tool_calls,
                   publish_status, remote_verification_status, error_message
            from automation_runs
            """
        ).fetchone()
        conn.close()

        assert row[:4] == ("pavbot-test", "research/test", "failed", "gpt-test")
        assert row[4:12] == (10, 3, 5, 2, 4, 7, "partial", "failed")
        assert "super-secret-token" not in row[12]
        assert "[REDACTED]" in row[12]


def test_usage_ledger_finish_tolerates_missing_token_fields() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        db = Path(tmp) / "usage-ledger.sqlite3"
        started = run_ledger(
            "--db",
            str(db),
            "start",
            "--automation-id",
            "pavbot-test",
            "--topic",
            "research/test",
        )
        run_id = json.loads(started.stdout)["runId"]

        finished = run_ledger("--db", str(db), "finish", "--run-id", run_id, "--status", "ok")

        assert finished.returncode == 0, finished.stderr
        conn = sqlite3.connect(db)
        row = conn.execute("select status, input_tokens from automation_runs").fetchone()
        conn.close()
        assert row == ("ok", None)
