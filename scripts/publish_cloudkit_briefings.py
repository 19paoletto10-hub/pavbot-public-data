#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


DEFAULT_CONTAINER_ID = "iCloud.com.paweltanski.pavbotviewer"
DEFAULT_ENVIRONMENT = "production"
DEFAULT_TEAM_ID = "SP774TZZU8"
DEFAULT_MANIFEST_URL = (
    "https://raw.githubusercontent.com/19paoletto10-hub/"
    "pavbot-public-data/main/public/pavbot-manifest.json"
)
BRIEFING_RECORD_TYPE = "Briefing"
READY_STATUS = "ready"
DEFAULT_CKTOOL_TIMEOUT_SECONDS = 60
CKTOOL_BARE_FILTER_VALUE = re.compile(r"^[A-Za-z0-9_.:/-]+$")


class CloudKitPublisherError(RuntimeError):
    pass


class ConfigurationError(CloudKitPublisherError):
    pass


class CktoolCommandError(CloudKitPublisherError):
    pass


class CloudKitVerificationError(CloudKitPublisherError):
    pass


def load_manifest(path: str | Path) -> dict[str, Any]:
    with Path(path).open(encoding="utf-8") as handle:
        manifest = json.load(handle)
    if not isinstance(manifest, dict):
        raise ConfigurationError("manifest must be a JSON object")
    return manifest


def topic_slug_for_path(topic_path: str | None) -> str | None:
    if topic_path is None:
        return None
    value = topic_path.strip().strip("/")
    if not value:
        return None
    if value.startswith("research/"):
        value = value.removeprefix("research/")
    return value or None


def artifact_stamp(artifact: dict[str, Any]) -> str | None:
    date = str(artifact.get("date") or "").strip()
    time_value = str(artifact.get("time") or "").strip()
    if date:
        if time_value:
            compact_time = re.sub(r"[^0-9]", "", time_value)
            if len(compact_time) >= 4:
                return f"{date}-{compact_time[:4]}"
        return date
    match = re.search(r"\d{4}-\d{2}-\d{2}(?:-\d{4})?", str(artifact.get("path") or artifact.get("id") or ""))
    return match.group(0) if match else None


def normalize_datetime_string(value: str) -> str:
    value = value.strip()
    if value.endswith("Z"):
        value = value[:-1] + "+00:00"
    try:
        return datetime.fromisoformat(value).astimezone(timezone.utc).replace(microsecond=0).isoformat()
    except ValueError:
        return value


def created_at_for_stamp(stamp: str, artifacts: list[dict[str, Any]]) -> str:
    for artifact in artifacts:
        value = artifact.get("createdAt") or artifact.get("generatedAt")
        if isinstance(value, str) and value.strip():
            return normalize_datetime_string(value)
    match = re.fullmatch(r"(\d{4}-\d{2}-\d{2})(?:-(\d{2})(\d{2}))?", stamp)
    if not match:
        return datetime.now(timezone.utc).replace(microsecond=0).isoformat()
    date_part, hour, minute = match.groups()
    if hour and minute:
        return datetime.fromisoformat(f"{date_part}T{hour}:{minute}:00+00:00").isoformat()
    return datetime.fromisoformat(f"{date_part}T00:00:00+00:00").isoformat()


def human_stamp(stamp: str) -> str:
    match = re.fullmatch(r"(\d{4}-\d{2}-\d{2})(?:-(\d{2})(\d{2}))?", stamp)
    if not match:
        return stamp
    date_part, hour, minute = match.groups()
    return f"{date_part} {hour}:{minute}" if hour and minute else date_part


def notification_title(topic_title: str, stamp: str) -> str:
    return f"{topic_title} · {human_stamp(stamp)}"


def briefing_summary(topic_title: str, stamp: str, artifacts: list[dict[str, Any]]) -> str:
    artifact_types = sorted({str(artifact.get("type")) for artifact in artifacts if artifact.get("type")})
    suffix = f" Artefakty: {', '.join(artifact_types)}." if artifact_types else ""
    return f"{topic_title}: nowe dane z publikacji {human_stamp(stamp)} są gotowe w aplikacji Pavbot.{suffix}"


def first_artifact_url(artifacts: list[dict[str, Any]], predicate) -> str | None:
    for artifact in sorted(artifacts, key=lambda item: str(item.get("path") or "")):
        if predicate(artifact):
            value = str(artifact.get("url") or "").strip()
            if value:
                return value
    return None


def is_audio_artifact(artifact: dict[str, Any]) -> bool:
    path = str(artifact.get("path") or "").lower()
    artifact_type = str(artifact.get("type") or "").lower()
    return path.endswith((".mp3", ".m4a", ".aac", ".wav", ".caf")) or "audio" in artifact_type


def is_image_artifact(artifact: dict[str, Any]) -> bool:
    return str(artifact.get("path") or "").lower().endswith((".jpg", ".jpeg", ".png", ".webp", ".heic"))


def build_briefing_records(
    manifest: dict[str, Any],
    manifest_url: str,
    topic_path: str | None = None,
) -> list[dict[str, Any]]:
    topic_filter = topic_slug_for_path(topic_path)
    topics = {
        str(topic.get("slug")): topic
        for topic in manifest.get("topics", [])
        if isinstance(topic, dict) and topic.get("slug")
    }
    groups: dict[tuple[str, str], list[dict[str, Any]]] = {}
    for artifact in manifest.get("artifacts", []):
        if not isinstance(artifact, dict):
            continue
        topic = str(artifact.get("topic") or "").strip()
        stamp = artifact_stamp(artifact)
        path = str(artifact.get("path") or "").strip()
        if not topic or not stamp or not path:
            continue
        if topic_filter and topic != topic_filter:
            continue
        groups.setdefault((topic, stamp), []).append(artifact)

    latest_by_topic: dict[str, tuple[str, list[dict[str, Any]]]] = {}
    for (topic, stamp), artifacts in groups.items():
        current = latest_by_topic.get(topic)
        if current is None or stamp > current[0]:
            latest_by_topic[topic] = (stamp, artifacts)

    records: list[dict[str, Any]] = []
    for topic, (stamp, artifacts) in sorted(latest_by_topic.items()):
        topic_title = str(topics.get(topic, {}).get("title") or topic)
        briefing_id = f"{topic}:{stamp}"
        fields = {
            "briefingId": briefing_id,
            "title": notification_title(topic_title, stamp),
            "summary": briefing_summary(topic_title, stamp, artifacts),
            "manifestUrl": manifest_url,
            "audioUrl": first_artifact_url(artifacts, is_audio_artifact),
            "imageUrl": first_artifact_url(artifacts, is_image_artifact),
            "createdAt": created_at_for_stamp(stamp, artifacts),
            "locale": "pl-PL",
            "category": topic,
            "status": READY_STATUS,
            "version": 1,
        }
        records.append(
            {
                "recordType": BRIEFING_RECORD_TYPE,
                "recordName": briefing_id,
                "fields": fields,
                "artifactPaths": sorted({str(artifact.get("path")) for artifact in artifacts if artifact.get("path")}),
            }
        )
    return records


def build_notification_payload(record: dict[str, Any]) -> dict[str, Any]:
    fields = record["fields"]
    title = str(fields["title"])
    return {
        "aps": {
            "alert": {
                "title": "Pavbot",
                "subtitle": title,
                "body": f"Nowe dane: {title}",
            },
            "sound": "default",
        },
        "briefingId": str(fields["briefingId"]),
        "category": str(fields["category"]),
        "manifestUrl": str(fields["manifestUrl"]),
    }


def records_with_notification_payload(records: list[dict[str, Any]]) -> list[dict[str, Any]]:
    enriched: list[dict[str, Any]] = []
    for record in records:
        clone = json.loads(json.dumps(record, ensure_ascii=False))
        clone["notificationPayload"] = build_notification_payload(record)
        enriched.append(clone)
    return enriched


def validate_config(args: argparse.Namespace) -> None:
    errors: list[str] = []
    if args.container_id != DEFAULT_CONTAINER_ID:
        errors.append(f"container id {args.container_id!r}; expected {DEFAULT_CONTAINER_ID}")
    if args.environment != DEFAULT_ENVIRONMENT:
        errors.append(f"environment {args.environment!r}; expected {DEFAULT_ENVIRONMENT}")
    if args.team_id != DEFAULT_TEAM_ID:
        errors.append(f"team id {args.team_id!r}; expected {DEFAULT_TEAM_ID}")
    if not args.manifest_url.startswith("https://raw.githubusercontent.com/") or not args.manifest_url.endswith(
        "/public/pavbot-manifest.json"
    ):
        errors.append("manifest URL must be a GitHub raw public/pavbot-manifest.json URL")
    if args.topic is None and not args.all_topics:
        errors.append("pass --topic research/<topic> or --all-topics")
    if args.topic is not None and topic_slug_for_path(args.topic) is None:
        errors.append("topic must be a non-empty research/<topic> path")
    if errors:
        raise ConfigurationError("Invalid production CloudKit configuration: " + "; ".join(errors))


def timestamp_for_cktool(value: str) -> str:
    normalized = normalize_datetime_string(value)
    return normalized[:-6] + "Z" if normalized.endswith("+00:00") else normalized


def cktool_typed_fields(fields: dict[str, Any]) -> dict[str, dict[str, Any]]:
    typed: dict[str, dict[str, Any]] = {}
    for key, value in fields.items():
        if value is None:
            continue
        if isinstance(value, bool):
            typed[key] = {"type": "int64Type", "value": 1 if value else 0}
        elif isinstance(value, int):
            typed[key] = {"type": "int64Type", "value": value}
        elif key == "createdAt":
            typed[key] = {"type": "timestampType", "value": timestamp_for_cktool(str(value))}
        else:
            typed[key] = {"type": "stringType", "value": str(value)}
    return typed


def cktool_filter_value(value: str) -> str:
    if CKTOOL_BARE_FILTER_VALUE.fullmatch(value):
        return value
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'


def briefing_filter(record: dict[str, Any]) -> str:
    return f"briefingId == {cktool_filter_value(str(record['fields']['briefingId']))}"


def cktool_base_args(args: argparse.Namespace, subcommand: str, include_team_id: bool = True) -> list[str]:
    command = ["xcrun", "cktool", subcommand]
    if include_team_id:
        command += ["--team-id", args.team_id]
    command += [
        "--container-id",
        args.container_id,
        "--environment",
        args.environment,
        "--database-type",
        "public",
    ]
    return command


def run_cktool(command: list[str]) -> subprocess.CompletedProcess[str]:
    timeout = int(os.environ.get("PAVBOT_CLOUDKIT_TIMEOUT_SECONDS", str(DEFAULT_CKTOOL_TIMEOUT_SECONDS)))
    result = subprocess.run(command, text=True, capture_output=True, timeout=timeout, check=False)
    if result.returncode != 0:
        stderr = (result.stderr or "").strip()
        raise CktoolCommandError(f"cktool command failed: {' '.join(command[:3])} ... {stderr}")
    return result


def cktool_records(stdout: str) -> list[dict[str, Any]]:
    try:
        payload = json.loads(stdout)
    except json.JSONDecodeError as error:
        raise CktoolCommandError("cktool returned non-JSON output") from error
    records = payload.get("records") if isinstance(payload, dict) else None
    return [record for record in records if isinstance(record, dict)] if isinstance(records, list) else []


def query_existing_records(record: dict[str, Any], args: argparse.Namespace) -> list[dict[str, Any]]:
    command = cktool_base_args(args, "query-records") + [
        "--record-type",
        record["recordType"],
        "--filters",
        briefing_filter(record),
        "--limit",
        "10",
    ]
    return cktool_records(run_cktool(command).stdout)


def delete_existing_records(record: dict[str, Any], args: argparse.Namespace) -> None:
    command = cktool_base_args(args, "delete-records", include_team_id=False) + [
        "--record-type",
        record["recordType"],
        "--filters",
        briefing_filter(record),
        "--dry-run",
        "false",
        "--yes",
    ]
    run_cktool(command)


def publish_records(records: list[dict[str, Any]], args: argparse.Namespace) -> None:
    for record in records:
        if query_existing_records(record, args):
            delete_existing_records(record, args)
        fields_json = json.dumps(cktool_typed_fields(record["fields"]), ensure_ascii=False, separators=(",", ":"))
        command = cktool_base_args(args, "create-record") + [
            "--record-type",
            record["recordType"],
            "--fields-json",
            fields_json,
        ]
        run_cktool(command)


def verify_records(records: list[dict[str, Any]], args: argparse.Namespace) -> None:
    missing: list[str] = []
    for record in records:
        existing = query_existing_records(record, args)
        if not existing:
            missing.append(str(record["fields"]["briefingId"]))
    if missing:
        raise CloudKitVerificationError("missing CloudKit Briefing records: " + ", ".join(missing))


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Publish Pavbot manifest Briefing records to production CloudKit.")
    parser.add_argument("mode", choices=["dry-run", "preflight", "publish", "verify"])
    parser.add_argument("--manifest", default="public/pavbot-manifest.json")
    parser.add_argument("--manifest-url", default=os.environ.get("PAVBOT_MANIFEST_URL", DEFAULT_MANIFEST_URL))
    parser.add_argument("--container-id", default=os.environ.get("PAVBOT_CLOUDKIT_CONTAINER_ID", DEFAULT_CONTAINER_ID))
    parser.add_argument("--environment", default=os.environ.get("PAVBOT_CLOUDKIT_ENVIRONMENT", DEFAULT_ENVIRONMENT))
    parser.add_argument("--team-id", default=os.environ.get("PAVBOT_CLOUDKIT_TEAM_ID", DEFAULT_TEAM_ID))
    parser.add_argument("--topic")
    parser.add_argument("--all-topics", action="store_true")
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    try:
        validate_config(args)
        records = build_briefing_records(load_manifest(args.manifest), args.manifest_url, args.topic)
        if not records:
            raise CloudKitVerificationError("no Briefing records were derived from the manifest")
        if args.mode == "dry-run" or os.environ.get("PAVBOT_CLOUDKIT_DRY_RUN") == "1":
            print(json.dumps({"records": records_with_notification_payload(records)}, ensure_ascii=False, indent=2))
            return 0
        if args.mode == "preflight":
            for record in records:
                query_existing_records(record, args)
            return 0
        if args.mode == "publish":
            publish_records(records, args)
            return 0
        if args.mode == "verify":
            verify_records(records, args)
            return 0
        raise AssertionError(f"unexpected mode: {args.mode}")
    except CloudKitPublisherError as error:
        print(f"error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
