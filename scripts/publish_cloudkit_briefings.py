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
DEFAULT_APNS_KEY_ID = "YWVNV6YGXJ"
DEFAULT_MANIFEST_URL = (
    "https://raw.githubusercontent.com/19paoletto10-hub/"
    "pavbot-public-data/main/public/pavbot-manifest.json"
)
BRIEFING_RECORD_TYPE = "Briefing"
READY_STATUS = "ready"
CKTOOL_BARE_FILTER_VALUE = re.compile(r"^[A-Za-z0-9_.:/-]+$")
DEFAULT_CKTOOL_TIMEOUT_SECONDS = 60
MIN_CKTOOL_TIMEOUT_SECONDS = 5
MAX_CKTOOL_TIMEOUT_SECONDS = 300


class CloudKitPublisherError(RuntimeError):
    """Base error for operator-facing CloudKit publisher failures."""


class ConfigurationError(CloudKitPublisherError):
    pass


class CktoolAuthError(CloudKitPublisherError):
    pass


class CktoolCommandError(CloudKitPublisherError):
    pass


class CloudKitVerificationError(CloudKitPublisherError):
    pass


class PublisherConfig:
    def __init__(
        self,
        *,
        manifest: str,
        manifest_url: str,
        container_id: str,
        environment: str,
        team_id: str,
        topic: str | None,
        all_topics: bool,
    ) -> None:
        self.manifest = manifest
        self.manifest_url = manifest_url
        self.container_id = container_id
        self.environment = environment
        self.team_id = team_id
        self.topic = topic
        self.all_topics = all_topics

    @classmethod
    def from_args(cls, args: argparse.Namespace) -> "PublisherConfig":
        config = cls(
            manifest=args.manifest,
            manifest_url=args.manifest_url,
            container_id=args.container_id,
            environment=args.environment,
            team_id=args.team_id,
            topic=args.topic,
            all_topics=args.all_topics,
        )
        validate_publisher_config(config)
        return config


def validate_publisher_config(config: PublisherConfig) -> None:
    errors: list[str] = []
    if config.container_id != DEFAULT_CONTAINER_ID:
        errors.append(f"container id {config.container_id!r}; expected {DEFAULT_CONTAINER_ID}")
    if config.environment.lower() != DEFAULT_ENVIRONMENT:
        errors.append(f"environment {config.environment!r}; expected {DEFAULT_ENVIRONMENT}")
    if config.team_id != DEFAULT_TEAM_ID:
        errors.append(f"team id {config.team_id!r}; expected {DEFAULT_TEAM_ID}")
    if not config.manifest_url.startswith("https://raw.githubusercontent.com/") or not config.manifest_url.endswith(
        "/public/pavbot-manifest.json"
    ):
        errors.append("manifest URL must be a GitHub raw HTTPS public/pavbot-manifest.json URL")
    if config.topic is not None and topic_slug_for_path(config.topic) is None:
        errors.append("topic must be a non-empty research/<topic> path")
    if errors:
        raise ConfigurationError("Invalid production CloudKit configuration: " + "; ".join(errors))


def load_manifest(path: str | Path) -> dict[str, Any]:
    manifest_path = Path(path)
    with manifest_path.open(encoding="utf-8") as handle:
        manifest = json.load(handle)
    if not isinstance(manifest, dict):
        raise ValueError(f"manifest must be a JSON object: {manifest_path}")
    return manifest


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
        created_at = created_at_for_stamp(stamp, artifacts)
        audio_url = first_artifact_url(artifacts, is_audio_artifact)
        image_url = first_artifact_url(artifacts, is_image_artifact)
        title = notification_title(topic_title, stamp)
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


def notification_title(topic_title: str, stamp: str) -> str:
    return f"{topic_title} · {human_stamp(stamp)}"


def briefing_summary(topic_title: str, stamp: str, artifacts: list[dict[str, Any]]) -> str:
    artifact_types = sorted(
        {
            str(artifact.get("type"))
            for artifact in artifacts
            if artifact.get("type")
        }
    )
    suffix = f" Artefakty: {', '.join(artifact_types)}." if artifact_types else ""
    return f"{topic_title}: nowe dane z publikacji {human_stamp(stamp)} są gotowe w aplikacji Pavbot.{suffix}"


def human_stamp(stamp: str) -> str:
    match = re.fullmatch(r"(\d{4}-\d{2}-\d{2})(?:-(\d{2})(\d{2}))?", stamp)
    if not match:
        return stamp
    date_part, hour, minute = match.groups()
    if hour and minute:
        return f"{date_part} {hour}:{minute}"
    return date_part


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


def cktool_timeout_seconds() -> int:
    raw_value = os.environ.get("PAVBOT_CLOUDKIT_TIMEOUT_SECONDS")
    if not raw_value:
        return DEFAULT_CKTOOL_TIMEOUT_SECONDS
    try:
        value = int(raw_value)
    except ValueError as error:
        raise ConfigurationError("PAVBOT_CLOUDKIT_TIMEOUT_SECONDS must be an integer") from error
    if value < MIN_CKTOOL_TIMEOUT_SECONDS or value > MAX_CKTOOL_TIMEOUT_SECONDS:
        raise ConfigurationError(
            "PAVBOT_CLOUDKIT_TIMEOUT_SECONDS must be between "
            f"{MIN_CKTOOL_TIMEOUT_SECONDS} and {MAX_CKTOOL_TIMEOUT_SECONDS}"
        )
    return value


def safe_cktool_command(command: list[str]) -> str:
    safe: list[str] = []
    redact_next = False
    for part in command:
        if redact_next:
            safe.append("<redacted>")
            redact_next = False
            continue
        safe.append(part)
        if part in {"--fields-json", "--user-token", "--management-token"}:
            redact_next = True
    return " ".join(safe)


def run_cktool(command: list[str], *, check: bool = True) -> subprocess.CompletedProcess[str]:
    timeout = cktool_timeout_seconds()
    try:
        result = subprocess.run(command, text=True, capture_output=True, timeout=timeout)
    except subprocess.TimeoutExpired as error:
        raise CktoolCommandError(
            f"cktool timed out after {timeout}s while running {safe_cktool_command(command)}"
        ) from error
    if result.returncode != 0 and cktool_auth_is_missing(result.stderr):
        raise CktoolAuthError(cktool_auth_error_message())
    if check and result.returncode != 0:
        raise CktoolCommandError(cktool_failure_message(result, command))
    return result


def cktool_failure_message(result: subprocess.CompletedProcess[str], command: list[str]) -> str:
    stderr = (result.stderr or "").strip()
    normalized = stderr.lower()
    if "container" in normalized:
        hint = f"Confirm CloudKit container {DEFAULT_CONTAINER_ID} is enabled for team {DEFAULT_TEAM_ID}."
    elif "team" in normalized:
        hint = f"Confirm Apple Developer team {DEFAULT_TEAM_ID} is selected for cktool."
    elif "record type" in normalized or "schema" in normalized or BRIEFING_RECORD_TYPE.lower() in normalized:
        hint = "Confirm the production CloudKit schema contains public record type Briefing and required indexes."
    else:
        hint = "Run `xcrun cktool save-token` if authentication is stale, then retry or use --cloudkit-only after a verified push."
    details = f": {stderr}" if stderr else ""
    return f"cktool command failed ({safe_cktool_command(command)}){details}. {hint}"


def cktool_auth_is_missing(stderr: str) -> bool:
    normalized = stderr.lower()
    return any(
        marker in normalized
        for marker in (
            "no user token found",
            "no management token found",
            "session has expired",
            "authentication failed",
            "user token may have been entered incorrectly",
            "user token may have expired",
            "user token may be required",
            "new user token may be required",
        )
    )


def cktool_auth_error_message() -> str:
    return (
        "CloudKit cktool authentication is missing or expired. Run "
        "`xcrun cktool save-token` for Apple Developer team SP774TZZU8, "
        "then rerun the Pavbot publish or `--cloudkit-only` repair command."
    )


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
        raise CktoolCommandError("cktool returned non-JSON output") from error
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
    return f"briefingId == {cktool_filter_value(briefing_id)}"


def cktool_filter_value(value: str) -> str:
    if CKTOOL_BARE_FILTER_VALUE.fullmatch(value):
        return value
    escaped = value.replace("\\", "\\\\").replace('"', '\\"')
    return f'"{escaped}"'


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


def preflight_records(records: list[dict[str, Any]], container_id: str, environment: str, team_id: str) -> None:
    for record in records:
        query_existing_records(
            record,
            container_id=container_id,
            environment=environment,
            team_id=team_id,
        )


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
            "--limit",
            "1",
        ]
        result = run_cktool(command, check=False)
        if result.returncode != 0:
            if cktool_auth_is_missing(result.stderr):
                raise RuntimeError(cktool_auth_error_message())
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
        expected_manifest_url = record["fields"].get("manifestUrl")
        expected_category = record["fields"].get("category")
        if not any(
            cktool_field_value(item, "briefingId") == briefing_id
            and cktool_field_value(item, "status") == READY_STATUS
            and cktool_field_value(item, "manifestUrl") == expected_manifest_url
            and cktool_field_value(item, "category") == expected_category
            for item in records_payload
        ):
            missing.append(record["recordName"])
    if missing:
        raise CloudKitVerificationError("CloudKit verification missing ready records: " + ", ".join(missing))


def parse_args(argv: list[str] | None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Publish Pavbot Briefing records to CloudKit.")
    parser.add_argument("mode", choices=("dry-run", "preflight", "publish", "verify"))
    parser.add_argument("--manifest", default="public/pavbot-manifest.json")
    parser.add_argument("--manifest-url", default=os.environ.get("PAVBOT_MANIFEST_URL", DEFAULT_MANIFEST_URL))
    parser.add_argument("--container-id", default=os.environ.get("PAVBOT_CLOUDKIT_CONTAINER_ID", DEFAULT_CONTAINER_ID))
    parser.add_argument("--environment", default=os.environ.get("PAVBOT_CLOUDKIT_ENVIRONMENT", DEFAULT_ENVIRONMENT))
    parser.add_argument("--team-id", default=os.environ.get("PAVBOT_CLOUDKIT_TEAM_ID", DEFAULT_TEAM_ID))
    parser.add_argument("--topic", default=None, help="Publish only the active research/<topic> briefing.")
    parser.add_argument("--all-topics", action="store_true", help="Backfill or verify all latest topic briefings.")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    try:
        config = PublisherConfig.from_args(args)
        manifest = load_manifest(config.manifest)
        records = build_briefing_records(
            manifest,
            manifest_url=config.manifest_url,
            topic_path=None if config.all_topics else config.topic,
        )
        if not records:
            raise CloudKitPublisherError("manifest did not produce any Briefing records")

        if args.mode == "dry-run":
            dry_run_records = [
                {
                    **record,
                    "notificationPayload": build_notification_payload(record),
                }
                for record in records
            ]
            print(json.dumps({"status": "dry-run", "records": dry_run_records}, ensure_ascii=False, indent=2))
            return 0

        if args.mode == "preflight":
            preflight_records(records, config.container_id, config.environment, config.team_id)
            print(json.dumps({"status": "preflight-ok", "recordCount": len(records)}, ensure_ascii=False))
            return 0

        if args.mode == "publish":
            publish_records(records, config.container_id, config.environment, config.team_id)
            print(json.dumps({"status": "published", "recordCount": len(records)}, ensure_ascii=False))
            return 0

        verify_records(records, config.container_id, config.environment, config.team_id)
        print(json.dumps({"status": "verified", "recordCount": len(records)}, ensure_ascii=False))
        return 0
    except Exception as error:
        print(f"CloudKit briefing publication failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
