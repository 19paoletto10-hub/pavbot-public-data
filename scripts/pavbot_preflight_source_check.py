#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import urllib.request
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


DEFAULT_STATE_FILE = Path(".pavbot/private/preflight-source-state.json")


def utc_now() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def sha256_bytes(payload: bytes) -> str:
    return hashlib.sha256(payload).hexdigest()


def read_source(ref: str, timeout: float) -> tuple[str, bytes | None, str | None]:
    if ref.startswith(("http://", "https://")):
        try:
            request = urllib.request.Request(ref, headers={"User-Agent": "pavbot-preflight/1.0"})
            with urllib.request.urlopen(request, timeout=timeout) as response:
                return "ok", response.read(), None
        except Exception as exc:  # noqa: BLE001 - preflight must degrade to unknown.
            return "unreachable", None, str(exc)

    path = Path(ref.removeprefix("file://"))
    try:
        return "ok", path.read_bytes(), None
    except OSError as exc:
        return "unreachable", None, str(exc)


def parse_source(value: str) -> tuple[str, str]:
    if "=" in value:
        name, ref = value.split("=", 1)
        return name.strip() or ref.strip(), ref.strip()
    return Path(value).name or value, value


def load_json_file(path: Path) -> dict[str, Any]:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return {}


def latest_manifest_path(manifest_path: Path, topic_path: str) -> str | None:
    manifest = load_json_file(manifest_path)
    artifacts = [
        artifact
        for artifact in manifest.get("artifacts", [])
        if isinstance(artifact, dict) and str(artifact.get("path", "")).startswith(f"{topic_path}/")
    ]
    if not artifacts:
        return None
    artifacts.sort(key=lambda item: (item.get("date") or "", item.get("time") or "", item.get("path") or ""))
    return str(artifacts[-1].get("path") or "") or None


def build_result(args: argparse.Namespace) -> tuple[dict[str, Any], dict[str, Any]]:
    topic_path = str(Path(args.topic_path).as_posix()).rstrip("/")
    state_path = Path(args.state_file)
    previous_state = load_json_file(state_path)
    state_key = f"{args.automation_id}|{topic_path}"
    previous_sources = previous_state.get(state_key, {}).get("sources", {})
    next_sources: dict[str, Any] = {}
    source_results: list[dict[str, Any]] = []

    any_unreachable = False
    any_changed = False
    missing_previous = state_key not in previous_state

    for source_arg in args.source:
        name, ref = parse_source(source_arg)
        status, content, error = read_source(ref, args.timeout)
        entry: dict[str, Any] = {"name": name, "ref": ref, "status": status}
        if status != "ok" or content is None:
            any_unreachable = True
            entry["changed"] = None
            entry["error"] = error or "unreachable"
            source_results.append(entry)
            continue

        digest = sha256_bytes(content)
        previous_digest = previous_sources.get(name, {}).get("sha256")
        changed = previous_digest is not None and previous_digest != digest
        if changed:
            any_changed = True
        entry.update(
            {
                "sha256": digest,
                "bytes": len(content),
                "changed": changed if previous_digest is not None else None,
            }
        )
        next_sources[name] = {"ref": ref, "sha256": digest, "bytes": len(content), "checkedAt": utc_now()}
        source_results.append(entry)

    if any_unreachable:
        hint = "unknown"
        reason = "source_unreachable"
    elif missing_previous:
        hint = "unknown"
        reason = "no_previous_state"
    elif any_changed:
        hint = "yes"
        reason = "source_hash_changed"
    else:
        hint = "no"
        reason = "sources_unchanged"

    result = {
        "schemaVersion": 1,
        "automationId": args.automation_id,
        "topicPath": topic_path,
        "checkedAt": utc_now(),
        "materialChangeHint": hint,
        "reason": reason,
        "latestRemoteArtifact": latest_manifest_path(Path(args.baseline_manifest), topic_path)
        if args.baseline_manifest
        else None,
        "sources": source_results,
    }
    next_state = dict(previous_state)
    if next_sources:
        next_state[state_key] = {
            "automationId": args.automation_id,
            "topicPath": topic_path,
            "updatedAt": result["checkedAt"],
            "sources": next_sources,
        }
    return result, next_state


def main() -> int:
    parser = argparse.ArgumentParser(description="Run a cheap Pavbot source preflight.")
    parser.add_argument("topic_path")
    parser.add_argument("--automation-id", required=True)
    parser.add_argument("--source", action="append", default=[], help="Source as name=path_or_url")
    parser.add_argument("--state-file", default=str(DEFAULT_STATE_FILE))
    parser.add_argument("--baseline-manifest")
    parser.add_argument("--timeout", type=float, default=10.0)
    parser.add_argument("--update-state", action="store_true")
    parser.add_argument("--output")
    args = parser.parse_args()

    if not args.source:
        parser.error("at least one --source is required")

    result, next_state = build_result(args)
    payload = json.dumps(result, ensure_ascii=False, indent=2) + "\n"
    if args.output:
        output_path = Path(args.output)
        output_path.parent.mkdir(parents=True, exist_ok=True)
        output_path.write_text(payload, encoding="utf-8")

    if args.update_state:
        state_path = Path(args.state_file)
        state_path.parent.mkdir(parents=True, exist_ok=True)
        state_path.write_text(json.dumps(next_state, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    print(payload, end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
