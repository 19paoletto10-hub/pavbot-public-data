#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import re
import sqlite3
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


DEFAULT_DB = Path(".pavbot/private/usage-ledger.sqlite3")

SCHEMA = """
create table if not exists automation_runs (
  run_id text primary key,
  automation_id text not null,
  topic text not null,
  model text,
  started_at text not null,
  ended_at text,
  status text not null,
  input_tokens integer,
  cached_tokens integer,
  output_tokens integer,
  reasoning_tokens integer,
  web_calls integer,
  tool_calls integer,
  preflight_result text,
  publish_status text,
  remote_verification_status text,
  error_class text,
  error_message text
)
"""


def utc_now() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def connect(db_path: Path) -> sqlite3.Connection:
    db_path.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(db_path)
    conn.execute(SCHEMA)
    conn.commit()
    return conn


def optional_int(value: str | None) -> int | None:
    return int(value) if value not in (None, "") else None


def sanitize(value: str | None) -> str | None:
    if value is None:
        return None
    redacted = re.sub(r"(?i)(bearer\s+)[A-Za-z0-9._~+/=-]+", r"\1[REDACTED]", value)
    redacted = re.sub(
        r"(?i)(token|secret|key|password)(\s*[:=]\s*)[^\s,;]+",
        r"\1\2[REDACTED]",
        redacted,
    )
    return redacted


def normalize_json(value: str | None) -> str | None:
    if not value:
        return None
    parsed: Any = json.loads(value)
    return json.dumps(parsed, ensure_ascii=False, sort_keys=True)


def start(args: argparse.Namespace) -> int:
    run_id = str(uuid.uuid4())
    conn = connect(Path(args.db))
    conn.execute(
        """
        insert into automation_runs (
          run_id, automation_id, topic, model, started_at, status, preflight_result
        ) values (?, ?, ?, ?, ?, ?, ?)
        """,
        (
            run_id,
            args.automation_id,
            args.topic,
            args.model,
            utc_now(),
            "running",
            normalize_json(args.preflight_result),
        ),
    )
    conn.commit()
    conn.close()
    print(json.dumps({"runId": run_id}, ensure_ascii=False))
    return 0


def finish(args: argparse.Namespace) -> int:
    conn = connect(Path(args.db))
    conn.execute(
        """
        update automation_runs
        set ended_at = ?,
            status = ?,
            input_tokens = ?,
            cached_tokens = ?,
            output_tokens = ?,
            reasoning_tokens = ?,
            web_calls = ?,
            tool_calls = ?,
            publish_status = ?,
            remote_verification_status = ?,
            error_class = ?,
            error_message = ?
        where run_id = ?
        """,
        (
            utc_now(),
            args.status,
            optional_int(args.input_tokens),
            optional_int(args.cached_tokens),
            optional_int(args.output_tokens),
            optional_int(args.reasoning_tokens),
            optional_int(args.web_calls),
            optional_int(args.tool_calls),
            args.publish_status,
            args.remote_verification_status,
            sanitize(args.error_class),
            sanitize(args.error_message),
            args.run_id,
        ),
    )
    if conn.total_changes == 0:
        raise SystemExit(f"run id not found: {args.run_id}")
    conn.commit()
    conn.close()
    print(json.dumps({"runId": args.run_id, "status": args.status}, ensure_ascii=False))
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Record private Pavbot automation usage telemetry.")
    parser.add_argument("--db", default=str(DEFAULT_DB))
    subparsers = parser.add_subparsers(dest="command", required=True)

    start_parser = subparsers.add_parser("start")
    start_parser.add_argument("--automation-id", required=True)
    start_parser.add_argument("--topic", required=True)
    start_parser.add_argument("--model")
    start_parser.add_argument("--preflight-result")
    start_parser.set_defaults(func=start)

    finish_parser = subparsers.add_parser("finish")
    finish_parser.add_argument("--run-id", required=True)
    finish_parser.add_argument("--status", required=True)
    finish_parser.add_argument("--input-tokens")
    finish_parser.add_argument("--cached-tokens")
    finish_parser.add_argument("--output-tokens")
    finish_parser.add_argument("--reasoning-tokens")
    finish_parser.add_argument("--web-calls")
    finish_parser.add_argument("--tool-calls")
    finish_parser.add_argument("--publish-status")
    finish_parser.add_argument("--remote-verification-status")
    finish_parser.add_argument("--error-class")
    finish_parser.add_argument("--error-message")
    finish_parser.set_defaults(func=finish)

    args = parser.parse_args()
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
