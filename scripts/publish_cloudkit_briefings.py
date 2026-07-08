#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import time
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
ARTIFACT_RECORD_TYPE = "Artifact"
READY_STATUS = "ready"
DEFAULT_CKTOOL_TIMEOUT_SECONDS = 60
CKTOOL_BARE_FILTER_VALUE = re.compile(r"^[A-Za-z0-9_.:/-]+$")
PRIMARY_ARTIFACT_TYPE_PRIORITY = (
    "pulseNewsData",
    "redditRadarData",
    "mobileNewsData",
    "jobsData",
    "researchData",
    "pdf",
    "podcastAudioVariant",
    "podcastAudio",
    "run",
)


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


def notification_title(automation_name: str, stamp: str) -> str:
    return f"{automation_name} · {human_stamp(stamp)}"


def briefing_summary(automation_name: str, stamp: str, artifacts: list[dict[str, Any]]) -> str:
    artifact_types = sorted({str(artifact.get("type")) for artifact in artifacts if artifact.get("type")})
    suffix = f" Artefakty: {', '.join(artifact_types)}." if artifact_types else ""
    return f"Aktualizacja automatyzacji {automation_name}: publikacja {human_stamp(stamp)} jest gotowa w aplikacji Pavbot.{suffix}"


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


def latest_artifact_groups(
    manifest: dict[str, Any],
    topic_path: str | None = None,
) -> list[tuple[str, str, list[dict[str, Any]]]]:
    topic_filter = topic_slug_for_path(topic_path)
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

    return [(topic, stamp, artifacts) for topic, (stamp, artifacts) in sorted(latest_by_topic.items())]


def automation_topic_slug(automation: dict[str, Any]) -> str:
    topic = str(automation.get("topic") or "").strip()
    if topic:
        return topic_slug_for_path(topic) or topic
    return topic_slug_for_path(str(automation.get("topicPath") or "")) or ""


def enabled_automations_by_topic(manifest: dict[str, Any]) -> dict[str, list[dict[str, Any]]]:
    result: dict[str, list[dict[str, Any]]] = {}
    for automation in manifest.get("automations", []):
        if not isinstance(automation, dict):
            continue
        if not automation.get("enabled", True):
            continue
        automation_id = str(automation.get("id") or "").strip()
        topic = automation_topic_slug(automation)
        if not automation_id or not topic:
            continue
        result.setdefault(topic, []).append(automation)
    for topic, automations in result.items():
        automations.sort(key=lambda item: (str(item.get("kind") or ""), str(item.get("name") or ""), str(item.get("id") or "")))
    return result


def topic_titles(manifest: dict[str, Any]) -> dict[str, str]:
    return {
        str(topic.get("slug")): str(topic.get("title") or topic.get("slug"))
        for topic in manifest.get("topics", [])
        if isinstance(topic, dict) and topic.get("slug")
    }


def automation_is_podcast(automation: dict[str, Any]) -> bool:
    text = " ".join(
        str(automation.get(key) or "")
        for key in ("kind", "name", "output")
    ).lower()
    return "podcast" in text or "/podcasts/" in text


def artifact_is_podcast(artifact: dict[str, Any]) -> bool:
    path = artifact_path(artifact).lower()
    artifact_type = str(artifact.get("type") or "").lower()
    return "/podcasts/" in path or artifact_type.startswith("podcast") or "audio" in artifact_type


def fallback_automation(topic: str, titles: dict[str, str]) -> dict[str, Any]:
    title = titles.get(topic) or topic
    return {
        "id": topic,
        "name": title,
        "topic": topic,
        "topicPath": f"research/{topic}",
    }


def selected_automation_for_artifact(
    *,
    topic: str,
    artifact: dict[str, Any],
    automations_by_topic: dict[str, list[dict[str, Any]]],
    titles: dict[str, str],
) -> dict[str, Any]:
    candidates = automations_by_topic.get(topic, [])
    if not candidates:
        return fallback_automation(topic, titles)
    if len(candidates) == 1:
        return candidates[0]

    podcast_artifact = artifact_is_podcast(artifact)
    matching = [automation for automation in candidates if automation_is_podcast(automation) == podcast_artifact]
    if podcast_artifact and matching:
        return matching[0]
    if matching:
        research_like = [
            automation
            for automation in matching
            if "research" in str(automation.get("kind") or automation.get("name") or "").lower()
        ]
        return (research_like or matching)[0]
    return candidates[0]


def latest_automation_artifact_groups(
    manifest: dict[str, Any],
    topic_path: str | None = None,
) -> list[tuple[dict[str, Any], str, str, list[dict[str, Any]]]]:
    topic_filter = topic_slug_for_path(topic_path)
    automations_by_topic = enabled_automations_by_topic(manifest)
    titles = topic_titles(manifest)
    grouped: dict[tuple[str, str, str], tuple[dict[str, Any], str, str, list[dict[str, Any]]]] = {}

    for artifact in manifest.get("artifacts", []):
        if not isinstance(artifact, dict):
            continue
        topic = str(artifact.get("topic") or "").strip()
        stamp = artifact_stamp(artifact)
        path = artifact_path(artifact)
        if not topic or not stamp or not path:
            continue
        if topic_filter and topic != topic_filter:
            continue

        automation = selected_automation_for_artifact(
            topic=topic,
            artifact=artifact,
            automations_by_topic=automations_by_topic,
            titles=titles,
        )
        automation_id = str(automation.get("id") or topic).strip()
        key = (automation_id, topic, stamp)
        if key not in grouped:
            grouped[key] = (automation, topic, stamp, [])
        grouped[key][3].append(artifact)

    latest_by_automation: dict[tuple[str, str], tuple[dict[str, Any], str, str, list[dict[str, Any]]]] = {}
    for automation, topic, stamp, artifacts in grouped.values():
        automation_id = str(automation.get("id") or topic)
        latest_key = (automation_id, topic)
        current = latest_by_automation.get(latest_key)
        if current is None or stamp > current[2]:
            latest_by_automation[latest_key] = (automation, topic, stamp, artifacts)

    return sorted(
        latest_by_automation.values(),
        key=lambda item: (
            item[1],
            str(item[0].get("name") or item[0].get("id") or ""),
            item[2],
        ),
    )


def artifact_path(artifact: dict[str, Any]) -> str:
    return str(artifact.get("path") or "").strip()


def sorted_publication_artifacts(artifacts: list[dict[str, Any]]) -> list[dict[str, Any]]:
    return sorted(artifacts, key=lambda artifact: artifact_path(artifact))


def primary_artifact_id(artifacts: list[dict[str, Any]]) -> str | None:
    if not artifacts:
        return None
    priority = {artifact_type: index for index, artifact_type in enumerate(PRIMARY_ARTIFACT_TYPE_PRIORITY)}
    selected = min(
        artifacts,
        key=lambda artifact: (
            priority.get(str(artifact.get("type") or ""), len(priority)),
            artifact_path(artifact),
        ),
    )
    return artifact_path(selected) or None


def build_briefing_records(
    manifest: dict[str, Any],
    manifest_url: str,
    topic_path: str | None = None,
) -> list[dict[str, Any]]:
    records: list[dict[str, Any]] = []
    for automation, topic, stamp, artifacts in latest_automation_artifact_groups(manifest, topic_path):
        artifacts = sorted_publication_artifacts(artifacts)
        artifact_ids = [artifact_path(artifact) for artifact in artifacts if artifact_path(artifact)]
        automation_id = str(automation.get("id") or topic)
        automation_name = str(automation.get("name") or automation_id)
        briefing_id = f"{automation_id}:{stamp}"
        fields = {
            "briefingId": briefing_id,
            "title": notification_title(automation_name, stamp),
            "summary": briefing_summary(automation_name, stamp, artifacts),
            "manifestUrl": manifest_url,
            "artifactCount": len(artifact_ids),
            "primaryArtifactId": primary_artifact_id(artifacts),
            "artifactIdsJson": json.dumps(artifact_ids, ensure_ascii=False, separators=(",", ":")),
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


def build_artifact_records(
    manifest: dict[str, Any],
    manifest_url: str,
    topic_path: str | None = None,
) -> list[dict[str, Any]]:
    records: list[dict[str, Any]] = []
    for automation, topic, stamp, artifacts in latest_automation_artifact_groups(manifest, topic_path):
        briefing_id = f"{str(automation.get('id') or topic)}:{stamp}"
        for artifact in sorted_publication_artifacts(artifacts):
            path = artifact_path(artifact)
            if not path:
                continue
            fields = {
                "artifactId": path,
                "briefingId": briefing_id,
                "topic": topic,
                "stamp": stamp,
                "type": str(artifact.get("type") or ""),
                "title": str(artifact.get("title") or path),
                "path": path,
                "url": str(artifact.get("url") or ""),
                "sizeBytes": int(artifact.get("sizeBytes") or 0),
                "date": str(artifact.get("date") or ""),
                "time": str(artifact.get("time") or ""),
                "manifestUrl": manifest_url,
                "status": READY_STATUS,
                "createdAt": created_at_for_stamp(stamp, [artifact]),
                "version": 1,
            }
            records.append(
                {
                    "recordType": ARTIFACT_RECORD_TYPE,
                    "recordName": path,
                    "fields": fields,
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
                "body": f"Aktualizacja automatyzacji: {title}",
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
        message = f"cktool command failed: {' '.join(command[:3])} ... {stderr}"
        hint = cktool_auth_hint(stderr)
        if not hint:
            hint = cktool_schema_hint(stderr, command)
        if hint:
            message = f"{message}\n{hint}"
        raise CktoolCommandError(message)
    return result


def cktool_auth_hint(stderr: str) -> str | None:
    normalized = stderr.lower()
    auth_markers = (
        "session has expired",
        "session has expired or is invalid",
        "new user token may be required",
        "authentication failed",
        "user token may have been entered incorrectly",
        "authorization token",
    )
    if not any(marker in normalized for marker in auth_markers):
        return None
    return (
        "CloudKit database operations require a fresh cktool user token. "
        "For unattended automations, provide a fresh Apple Developer user token "
        "as PAVBOT_CKTOOL_USER_TOKEN and rerun the publish script. For manual "
        "repair, run: xcrun cktool save-token --type user --method keychain --force. "
        "Before retrying, unset CLOUDKIT_USER_TOKEN CLOUDKIT_MANAGEMENT_TOKEN PAVBOT_CLOUDKIT_DRY_RUN "
        "so stale environment tokens or diagnostic mode cannot override Keychain."
    )


def cktool_schema_hint(stderr: str, command: list[str]) -> str | None:
    normalized = stderr.lower()
    if "not-found" not in normalized:
        return None
    if "--record-type" not in command:
        return None
    record_type = command[command.index("--record-type") + 1]
    if record_type != ARTIFACT_RECORD_TYPE:
        return None
    return (
        "CloudKit Production does not expose the Artifact record type yet. "
        "Create/deploy record type Artifact in iCloud.com.paweltanski.pavbotviewer Production with fields "
        "artifactId, briefingId, topic, stamp, type, title, path, url, sizeBytes, date, time, manifestUrl, "
        "status, createdAt, and version, then rerun: scripts/pavbot_commit_and_push_outputs.sh --all-topics."
    )


def cktool_payload(stdout: str) -> dict[str, Any]:
    try:
        payload = json.loads(stdout)
    except json.JSONDecodeError as error:
        raise CktoolCommandError("cktool returned non-JSON output") from error
    return payload if isinstance(payload, dict) else {}


def cktool_records(stdout: str) -> list[dict[str, Any]]:
    payload = cktool_payload(stdout)
    records = payload.get("records") if isinstance(payload, dict) else None
    return [record for record in records if isinstance(record, dict)] if isinstance(records, list) else []


def record_unique_field(record: dict[str, Any]) -> str:
    if record.get("recordType") == ARTIFACT_RECORD_TYPE:
        return "artifactId"
    return "briefingId"


def query_records_by_type(record_type: str, args: argparse.Namespace) -> list[dict[str, Any]]:
    base_command = cktool_base_args(args, "query-records") + [
        "--record-type",
        record_type,
        "--limit",
        "200",
    ]
    all_records: list[dict[str, Any]] = []
    continuation_token: str | None = None
    while True:
        command = list(base_command)
        if continuation_token:
            command += ["--continuation-token", continuation_token]
        payload = cktool_payload(run_cktool(command).stdout)
        records = payload.get("records") if isinstance(payload, dict) else None
        for existing in records if isinstance(records, list) else []:
            if isinstance(existing, dict):
                all_records.append(existing)
        token = payload.get("continuationToken")
        continuation_token = token if isinstance(token, str) and token else None
        if not continuation_token:
            return all_records


def query_existing_records(record: dict[str, Any], args: argparse.Namespace) -> list[dict[str, Any]]:
    unique_field = record_unique_field(record)
    unique_value = str(record["fields"][unique_field])
    return [
        existing
        for existing in query_records_by_type(str(record["recordType"]), args)
        if cloudkit_field_value(existing, unique_field) == unique_value
    ]


def cloudkit_field_value(record: dict[str, Any], field_name: str) -> Any:
    fields = record.get("fields")
    if not isinstance(fields, dict):
        return None
    field = fields.get(field_name)
    if isinstance(field, dict):
        return field.get("value")
    return field


def cloudkit_values_match(expected: Any, actual: Any, field_name: str) -> bool:
    if expected is None:
        return actual is None or str(actual).strip() == ""
    if isinstance(expected, bool):
        try:
            return bool(int(actual)) == expected
        except (TypeError, ValueError):
            return str(actual).lower() in {"true", "yes"} if expected else str(actual).lower() in {"false", "no"}
    if isinstance(expected, int):
        try:
            return int(actual) == expected
        except (TypeError, ValueError):
            return False
    if field_name == "createdAt":
        return normalize_datetime_string(str(actual)) == normalize_datetime_string(str(expected))
    return str(actual) == str(expected)


def cloudkit_record_matches(existing: dict[str, Any], desired: dict[str, Any]) -> bool:
    desired_fields = desired.get("fields")
    if not isinstance(desired_fields, dict):
        return False
    for field_name, expected in desired_fields.items():
        if not cloudkit_values_match(expected, cloudkit_field_value(existing, field_name), field_name):
            return False
    return True


def delete_existing_record(record_name: str, args: argparse.Namespace) -> None:
    command = cktool_base_args(args, "delete-record", include_team_id=False) + [
        "--record-name",
        record_name,
        "--yes",
    ]
    run_cktool(command)


def publish_records(records: list[dict[str, Any]], args: argparse.Namespace) -> None:
    for record in records:
        existing_records = query_existing_records(record, args)
        matching_records = [existing for existing in existing_records if cloudkit_record_matches(existing, record)]
        if matching_records:
            for duplicate in existing_records:
                if duplicate is matching_records[0]:
                    continue
                record_name = duplicate.get("recordName")
                if isinstance(record_name, str) and record_name:
                    delete_existing_record(record_name, args)
            continue
        for existing in existing_records:
            record_name = existing.get("recordName")
            if isinstance(record_name, str) and record_name:
                delete_existing_record(record_name, args)
        create_record(record, args)


def create_record(record: dict[str, Any], args: argparse.Namespace) -> None:
    fields_json = json.dumps(cktool_typed_fields(record["fields"]), ensure_ascii=False, separators=(",", ":"))
    command = cktool_base_args(args, "create-record") + [
        "--record-type",
        record["recordType"],
        "--fields-json",
        fields_json,
    ]
    run_cktool(command)


def publish_missing_records(records: list[dict[str, Any]], args: argparse.Namespace) -> None:
    for record in records:
        existing_records = query_existing_records(record, args)
        if existing_records:
            for duplicate in existing_records[1:]:
                record_name = duplicate.get("recordName")
                if isinstance(record_name, str) and record_name:
                    delete_existing_record(record_name, args)
            continue
        create_record(record, args)


def delete_stale_artifact_records(artifact_records: list[dict[str, Any]], args: argparse.Namespace) -> None:
    expected_by_briefing: dict[str, set[str]] = {}
    for record in artifact_records:
        fields = record["fields"]
        expected_by_briefing.setdefault(str(fields["briefingId"]), set()).add(str(fields["artifactId"]))
    if not expected_by_briefing:
        return

    for existing in query_records_by_type(ARTIFACT_RECORD_TYPE, args):
        briefing_id = cloudkit_field_value(existing, "briefingId")
        artifact_id = cloudkit_field_value(existing, "artifactId")
        if briefing_id not in expected_by_briefing:
            continue
        if artifact_id in expected_by_briefing[str(briefing_id)]:
            continue
        record_name = existing.get("recordName")
        if isinstance(record_name, str) and record_name:
            delete_existing_record(record_name, args)


def publish_publication_records(
    briefing_records: list[dict[str, Any]],
    artifact_records: list[dict[str, Any]],
    args: argparse.Namespace,
    *,
    replace_briefings: bool = True,
) -> None:
    delete_stale_artifact_records(artifact_records, args)
    publish_records(artifact_records, args)
    if replace_briefings:
        publish_records(briefing_records, args)
    else:
        publish_missing_records(briefing_records, args)


def verify_records(records: list[dict[str, Any]], args: argparse.Namespace) -> None:
    max_attempts = int(os.environ.get("PAVBOT_CLOUDKIT_VERIFY_ATTEMPTS", "4"))
    retry_seconds = float(os.environ.get("PAVBOT_CLOUDKIT_VERIFY_RETRY_SECONDS", "1.5"))
    missing: list[str] = []
    for attempt in range(1, max_attempts + 1):
        missing = []
        for record in records:
            existing = query_existing_records(record, args)
            if not existing:
                field = record_unique_field(record)
                missing.append(str(record["fields"][field]))
        if not missing:
            return
        if attempt < max_attempts:
            time.sleep(retry_seconds)
    record_types = sorted({str(record.get("recordType") or "record") for record in records})
    raise CloudKitVerificationError(f"missing CloudKit {'/'.join(record_types)} records: " + ", ".join(missing))


def verify_artifact_sets(briefing_records: list[dict[str, Any]], artifact_records: list[dict[str, Any]], args: argparse.Namespace) -> None:
    expected_by_briefing: dict[str, set[str]] = {}
    for record in artifact_records:
        fields = record["fields"]
        expected_by_briefing.setdefault(str(fields["briefingId"]), set()).add(str(fields["path"]))

    existing_by_briefing: dict[str, set[str]] = {str(record["fields"]["briefingId"]): set() for record in briefing_records}
    for existing in query_records_by_type(ARTIFACT_RECORD_TYPE, args):
        briefing_id = cloudkit_field_value(existing, "briefingId")
        path = cloudkit_field_value(existing, "path")
        if isinstance(briefing_id, str) and briefing_id in existing_by_briefing and isinstance(path, str):
            existing_by_briefing[briefing_id].add(path)

    mismatches = [
        briefing_id
        for briefing_id, expected_paths in expected_by_briefing.items()
        if existing_by_briefing.get(briefing_id, set()) != expected_paths
    ]
    if mismatches:
        raise CloudKitVerificationError("CloudKit Artifact records do not match manifest for: " + ", ".join(sorted(mismatches)))


def verify_publication_records(
    briefing_records: list[dict[str, Any]],
    artifact_records: list[dict[str, Any]],
    args: argparse.Namespace,
) -> None:
    verify_records(briefing_records, args)
    verify_records(artifact_records, args)
    verify_artifact_sets(briefing_records, artifact_records, args)


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Publish Pavbot manifest Briefing and Artifact records to production CloudKit.")
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
        manifest = load_manifest(args.manifest)
        records = build_briefing_records(manifest, args.manifest_url, args.topic)
        artifacts = build_artifact_records(manifest, args.manifest_url, args.topic)
        if not records:
            raise CloudKitVerificationError("no Briefing records were derived from the manifest")
        if args.mode == "dry-run" or os.environ.get("PAVBOT_CLOUDKIT_DRY_RUN") == "1":
            print(json.dumps({"records": records_with_notification_payload(records), "artifacts": artifacts}, ensure_ascii=False, indent=2))
            return 0
        if args.mode == "preflight":
            for record in records:
                query_existing_records(record, args)
            for artifact in artifacts:
                query_existing_records(artifact, args)
            return 0
        if args.mode == "publish":
            publish_publication_records(records, artifacts, args, replace_briefings=not args.all_topics)
            return 0
        if args.mode == "verify":
            verify_publication_records(records, artifacts, args)
            return 0
        raise AssertionError(f"unexpected mode: {args.mode}")
    except CloudKitPublisherError as error:
        print(f"error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
