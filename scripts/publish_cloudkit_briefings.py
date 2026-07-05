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


def load_manifest(path: str | Path) -> dict[str, Any]:
    manifest_path = Path(path)
    with manifest_path.open(encoding="utf-8") as handle:
        manifest = json.load(handle)
    if not isinstance(manifest, dict):
        raise ValueError(f"manifest must be a JSON object: {manifest_path}")
    return manifest


def build_briefing_records(manifest: dict[str, Any], manifest_url: str) -> list[dict[str, Any]]:
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
        created_at = created_at_for_stamp(stamp, artifacts)
        audio_url = first_artifact_url(artifacts, is_audio_artifact)
        image_url = first_artifact_url(artifacts, is_image_artifact)
        primary_artifact = primary_artifact_for_summary(artifacts)
        title = str(primary_artifact.get("title") or topic_title)
        summary = briefing_summary(topic_title, stamp, artifacts)
        records.append(
            {
                "recordType": BRIEFING_RECORD_TYPE,
                "recordName": briefing_id,
                "fields": {
                    "briefingId": briefing_id,
                    "title": title,
                    "summary": summary,
                    "manifestUrl": manifest_url,
                    "audioUrl": audio_url,
                    "imageUrl": image_url,
                    "createdAt": created_at,
                    "locale": "pl-PL",
                    "category": topic,
                    "status": READY_STATUS,
                    "version": 1,
                },
                "artifactPaths": sorted(
                    {
                        str(artifact.get("path"))
                        for artifact in artifacts
                        if artifact.get("path")
                    }
                ),
            }
        )
    return records


def artifact_stamp(artifact: dict[str, Any]) -> str | None:
    date = str(artifact.get("date") or "").strip()
    time_value = str(artifact.get("time") or "").strip()
    if date:
        if time_value:
            compact_time = re.sub(r"[^0-9]", "", time_value)
            if len(compact_time) >= 4:
                return f"{date}-{compact_time[:4]}"
        return date

    path = str(artifact.get("path") or artifact.get("id") or "")
    match = re.search(r"\d{4}-\d{2}-\d{2}(?:-\d{4})?", path)
    return match.group(0) if match else None


def created_at_for_stamp(stamp: str, artifacts: list[dict[str, Any]]) -> str:
    explicit_values = [
        artifact.get("createdAt") or artifact.get("generatedAt")
        for artifact in artifacts
        if artifact.get("createdAt") or artifact.get("generatedAt")
    ]
    for value in explicit_values:
        if isinstance(value, str) and value.strip():
            return normalize_datetime_string(value)

    match = re.fullmatch(r"(\d{4}-\d{2}-\d{2})(?:-(\d{2})(\d{2}))?", stamp)
    if not match:
        return datetime.now(timezone.utc).replace(microsecond=0).isoformat()
    date_part, hour, minute = match.groups()
    if hour and minute:
        value = datetime.fromisoformat(f"{date_part}T{hour}:{minute}:00+00:00")
    else:
        value = datetime.fromisoformat(f"{date_part}T00:00:00+00:00")
    return value.isoformat()


def normalize_datetime_string(value: str) -> str:
    value = value.strip()
    if value.endswith("Z"):
        value = value[:-1] + "+00:00"
    try:
        return datetime.fromisoformat(value).astimezone(timezone.utc).replace(microsecond=0).isoformat()
    except ValueError:
        return value


def primary_artifact_for_summary(artifacts: list[dict[str, Any]]) -> dict[str, Any]:
    preferred_types = (
        "mobileNewsData",
        "pulseNewsData",
        "jobsData",
        "researchData",
        "redditRadarData",
        "run",
        "pdf",
    )
    for artifact_type in preferred_types:
        for artifact in artifacts:
            if artifact.get("type") == artifact_type:
                return artifact
    return artifacts[0] if artifacts else {}


def briefing_summary(topic_title: str, stamp: str, artifacts: list[dict[str, Any]]) -> str:
    artifact_types = sorted(
        {
            str(artifact.get("type"))
            for artifact in artifacts
            if artifact.get("type")
        }
    )
    suffix = f" Artefakty: {', '.join(artifact_types)}." if artifact_types else ""
    return f"{topic_title}: publikacja {stamp} jest gotowa w manifeście Pavbot.{suffix}"


def first_artifact_url(artifacts: list[dict[str, Any]], predicate) -> str | None:
    for artifact in sorted(artifacts, key=lambda item: str(item.get("path") or "")):
        if predicate(artifact):
            url = str(artifact.get("url") or "").strip()
            if url:
                return url
    return None


def is_audio_artifact(artifact: dict[str, Any]) -> bool:
    path = str(artifact.get("path") or "").lower()
    artifact_type = str(artifact.get("type") or "").lower()
    audio_extensions = (".mp3", ".m4a", ".aac", ".wav", ".caf")
    return path.endswith(audio_extensions) or "audio" in artifact_type


def is_image_artifact(artifact: dict[str, Any]) -> bool:
    path = str(artifact.get("path") or "").lower()
    return path.endswith((".jpg", ".jpeg", ".png", ".webp", ".heic"))


def cktool_base_command(container_id: str, environment: str) -> list[str]:
    return [
        "xcrun",
        "cktool",
    ]


def cktool_scoped_args(container_id: str, environment: str) -> list[str]:
    return [
        "--container-id",
        container_id,
        "--environment",
        environment,
        "--database-type",
        "public",
    ]


def run_cktool(command: list[str], *, check: bool = True) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(command, text=True, capture_output=True)
    if result.returncode != 0 and cktool_auth_is_missing(result.stderr):
        raise RuntimeError(
            "CloudKit cktool authentication is missing. Run `xcrun cktool save-token` "
            "for the Apple Developer team before publishing."
        )
    if check and result.returncode != 0:
        raise subprocess.CalledProcessError(
            result.returncode,
            command,
            output=result.stdout,
            stderr=result.stderr,
        )
    return result


def cktool_auth_is_missing(stderr: str) -> bool:
    return "No user token found" in stderr or "No management token found" in stderr


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


def timestamp_for_cktool(value: str) -> str:
    normalized = normalize_datetime_string(value)
    if normalized.endswith("+00:00"):
        return normalized[:-6] + "Z"
    return normalized


def cktool_records_from_stdout(stdout: str) -> list[dict[str, Any]]:
    try:
        payload = json.loads(stdout)
    except json.JSONDecodeError as error:
        raise RuntimeError("cktool returned non-JSON output") from error
    records = payload.get("records") if isinstance(payload, dict) else None
    if not isinstance(records, list):
        return []
    return [record for record in records if isinstance(record, dict)]


def cktool_field_value(record: dict[str, Any], field_name: str) -> Any:
    fields = record.get("fields")
    if not isinstance(fields, dict):
        return None
    value = fields.get(field_name)
    if isinstance(value, dict) and "value" in value:
        return value["value"]
    return value


def briefing_filter(record: dict[str, Any]) -> str:
    briefing_id = str(record["fields"]["briefingId"])
    escaped = briefing_id.replace("\\", "\\\\").replace('"', '\\"')
    return f'briefingId == "{escaped}"'


def query_existing_records(
    record: dict[str, Any],
    *,
    container_id: str,
    environment: str,
    team_id: str,
) -> list[dict[str, Any]]:
    command = cktool_base_command(container_id, environment) + [
        "query-records",
        "--team-id",
        team_id,
        *cktool_scoped_args(container_id, environment),
        "--record-type",
        record["recordType"],
        "--filters",
        briefing_filter(record),
        "--requested-fields",
        "briefingId",
        "status",
        "--limit",
        "10",
    ]
    result = run_cktool(command)
    return cktool_records_from_stdout(result.stdout)


def delete_records_for_briefing_id(
    record: dict[str, Any],
    *,
    container_id: str,
    environment: str,
) -> None:
    command = cktool_base_command(container_id, environment) + [
        "delete-records",
        *cktool_scoped_args(container_id, environment),
        "--record-type",
        record["recordType"],
        "--filters",
        briefing_filter(record),
        "--dry-run",
        "false",
        "--yes",
    ]
    run_cktool(command)


def publish_records(records: list[dict[str, Any]], container_id: str, environment: str, team_id: str) -> None:
    for record in records:
        existing_records = query_existing_records(
            record,
            container_id=container_id,
            environment=environment,
            team_id=team_id,
        )
        if existing_records:
            delete_records_for_briefing_id(
                record,
                container_id=container_id,
                environment=environment,
            )

        fields_json = json.dumps(cktool_typed_fields(record["fields"]), ensure_ascii=False, separators=(",", ":"))
        command = cktool_base_command(container_id, environment) + [
            "create-record",
            "--team-id",
            team_id,
            *cktool_scoped_args(container_id, environment),
            "--record-type",
            record["recordType"],
            "--fields-json",
            fields_json,
        ]
        run_cktool(command)


def verify_records(records: list[dict[str, Any]], container_id: str, environment: str, team_id: str) -> None:
    missing: list[str] = []
    for record in records:
        briefing_id = str(record["fields"]["briefingId"])
        command = cktool_base_command(container_id, environment) + [
            "query-records",
            "--team-id",
            team_id,
            *cktool_scoped_args(container_id, environment),
            "--record-type",
            record["recordType"],
            "--filters",
            briefing_filter(record),
            "--filters",
            'status == "ready"',
            "--requested-fields",
            "briefingId",
            "status",
            "--limit",
            "1",
        ]
        result = run_cktool(command, check=False)
        if result.returncode != 0:
            missing.append(record["recordName"])
            if result.stderr:
                print(result.stderr, file=sys.stderr, end="")
            continue
        try:
            records_payload = cktool_records_from_stdout(result.stdout)
        except RuntimeError as error:
            print(f"{error}: {record['recordName']}", file=sys.stderr)
            missing.append(record["recordName"])
            continue
        if not any(
            cktool_field_value(item, "briefingId") == briefing_id
            and cktool_field_value(item, "status") == READY_STATUS
            for item in records_payload
        ):
            missing.append(record["recordName"])
    if missing:
        raise RuntimeError("CloudKit verification missing ready records: " + ", ".join(missing))


def parse_args(argv: list[str] | None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Publish Pavbot Briefing records to CloudKit.")
    parser.add_argument("mode", choices=("dry-run", "publish", "verify"))
    parser.add_argument("--manifest", default="public/pavbot-manifest.json")
    parser.add_argument("--manifest-url", default=os.environ.get("PAVBOT_MANIFEST_URL", DEFAULT_MANIFEST_URL))
    parser.add_argument("--container-id", default=os.environ.get("PAVBOT_CLOUDKIT_CONTAINER_ID", DEFAULT_CONTAINER_ID))
    parser.add_argument("--environment", default=os.environ.get("PAVBOT_CLOUDKIT_ENVIRONMENT", DEFAULT_ENVIRONMENT))
    parser.add_argument("--team-id", default=os.environ.get("PAVBOT_CLOUDKIT_TEAM_ID", DEFAULT_TEAM_ID))
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    try:
        manifest = load_manifest(args.manifest)
        records = build_briefing_records(manifest, manifest_url=args.manifest_url)
        if not records:
            raise RuntimeError("manifest did not produce any Briefing records")

        if args.mode == "dry-run":
            print(json.dumps({"status": "dry-run", "records": records}, ensure_ascii=False, indent=2))
            return 0

        if args.mode == "publish":
            publish_records(records, args.container_id, args.environment, args.team_id)
            print(json.dumps({"status": "published", "recordCount": len(records)}, ensure_ascii=False))
            return 0

        verify_records(records, args.container_id, args.environment, args.team_id)
        print(json.dumps({"status": "verified", "recordCount": len(records)}, ensure_ascii=False))
        return 0
    except Exception as error:
        print(f"CloudKit briefing publication failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
