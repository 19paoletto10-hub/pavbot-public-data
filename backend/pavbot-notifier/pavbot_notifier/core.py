from __future__ import annotations

import hashlib
import hmac
import json
from dataclasses import dataclass
from pathlib import Path
from typing import Any


@dataclass(frozen=True)
class ManifestChanges:
    artifacts: list[dict[str, Any]]
    automations: list[dict[str, Any]]

    @property
    def has_changes(self) -> bool:
        return bool(self.artifacts or self.automations)


def compute_manifest_changes(
    previous: dict[str, Any] | None,
    current: dict[str, Any],
) -> ManifestChanges:
    if previous is None:
        return ManifestChanges(artifacts=[], automations=[])

    previous_artifact_ids = {item.get("id") for item in previous.get("artifacts", [])}
    previous_automation_ids = {item.get("id") for item in previous.get("automations", [])}

    artifacts = [
        item
        for item in current.get("artifacts", [])
        if item.get("id") and item.get("id") not in previous_artifact_ids
    ]
    automations = [
        item
        for item in current.get("automations", [])
        if item.get("enabled", True)
        and item.get("id")
        and item.get("id") not in previous_automation_ids
    ]

    artifacts.sort(
        key=lambda item: (
            item.get("date") or "",
            item.get("time") or "",
            item.get("path") or "",
        ),
        reverse=True,
    )
    automations.sort(key=lambda item: item.get("name") or item.get("id") or "")

    return ManifestChanges(artifacts=artifacts, automations=automations)


def verify_github_signature(secret: str, body: bytes, signature_header: str | None) -> bool:
    if not secret:
        return True
    if not signature_header or not signature_header.startswith("sha256="):
        return False

    expected = "sha256=" + hmac.new(secret.encode("utf-8"), body, hashlib.sha256).hexdigest()
    return hmac.compare_digest(expected, signature_header)


def normalized_public_notifier_url(value: str) -> str:
    return value.strip().rstrip("/")


def app_connection_defaults(*, manifest_url: str, public_notifier_url: str) -> dict[str, Any]:
    manifest_url = manifest_url.strip()
    public_notifier_url = normalized_public_notifier_url(public_notifier_url)
    if not manifest_url:
        raise ValueError("PAVBOT_MANIFEST_URL is not configured")
    if not public_notifier_url:
        raise ValueError("PAVBOT_PUBLIC_NOTIFIER_URL is not configured")
    if not manifest_url.startswith("https://") or not manifest_url.endswith(".json"):
        raise ValueError("PAVBOT_MANIFEST_URL must be an HTTPS JSON URL")
    if not public_notifier_url.startswith("https://"):
        raise ValueError("PAVBOT_PUBLIC_NOTIFIER_URL must be an HTTPS URL")
    return {
        "schemaVersion": 1,
        "manifestURL": manifest_url,
        "notificationServerURL": public_notifier_url,
        "statusURL": f"{public_notifier_url}/status",
    }


async def send_apns_change_notifications(
    *,
    devices: dict[str, Any],
    artifacts: list[dict[str, Any]],
    automations: list[dict[str, Any]],
    manifest_url_value: str,
    sender: Any,
) -> dict[str, Any]:
    summary: dict[str, Any] = {
        "attempted": 0,
        "sent": 0,
        "failed": 0,
        "skippedDevices": 0,
        "errors": [],
        "status": "skipped",
    }

    notification = build_change_notification(
        artifacts=artifacts,
        automations=automations,
        manifest_url_value=manifest_url_value,
    )
    if notification is None:
        return summary

    sender_configured = getattr(getattr(sender, "config", None), "is_configured", True)
    summary["apnsConfigured"] = bool(sender_configured)
    if not sender_configured:
        summary["skippedReason"] = "APNs is not configured"
        return summary

    for device_token, registration in devices.items():
        if not isinstance(registration, dict):
            summary["skippedDevices"] += 1
            continue
        if registration.get("manifestURL") and registration.get("manifestURL") != manifest_url_value:
            summary["skippedDevices"] += 1
            continue

        await send_apns_alert_safely(
            sender=sender,
            device_token=device_token,
            title=notification["title"],
            body=notification["body"],
            user_info=notification["userInfo"],
            summary=summary,
            kind="summary",
            item_id=notification["summaryID"],
        )

    summary["status"] = delivery_status(summary)
    return summary


def build_change_notification(
    *,
    artifacts: list[dict[str, Any]],
    automations: list[dict[str, Any]],
    manifest_url_value: str,
) -> dict[str, Any] | None:
    artifact_ids = [str(item.get("id", "")) for item in artifacts if item.get("id")]
    automation_ids = [str(item.get("id", "")) for item in automations if item.get("id")]
    if not artifact_ids and not automation_ids:
        return None

    artifact_topics = [str(item.get("topic", "")) for item in artifacts if item.get("topic")]
    artifact_dates = [str(item.get("date", "")) for item in artifacts if item.get("date")]
    topic = common_value(artifact_topics)
    date = common_value(artifact_dates)

    user_info: dict[str, Any] = {
        "manifestURL": manifest_url_value,
    }
    if artifact_ids:
        user_info["artifactIDs"] = artifact_ids
    if topic:
        user_info["artifactTopic"] = topic
    if date:
        user_info["artifactDate"] = date
    if automation_ids:
        user_info["automationIDs"] = automation_ids
        user_info["automationID"] = automation_ids[0]

    if artifact_ids:
        file_label = "file" if len(artifact_ids) == 1 else "files"
        topic_label = topic or "Pavbot"
        date_label = f" · {date}" if date else ""
        body = f"{topic_label}{date_label} · {len(artifact_ids)} new {file_label}"
    else:
        automation_label = "automation" if len(automation_ids) == 1 else "automations"
        body = f"{len(automation_ids)} new {automation_label}"

    return {
        "title": "Pavbot",
        "body": body,
        "userInfo": user_info,
        "summaryID": artifact_ids[0] if artifact_ids else automation_ids[0],
    }


def common_value(values: list[str]) -> str:
    unique_values = {value for value in values if value}
    if len(unique_values) == 1:
        return next(iter(unique_values))
    return ""


async def send_apns_alert_safely(
    *,
    sender: Any,
    device_token: str,
    title: str,
    body: str,
    user_info: dict[str, Any],
    summary: dict[str, Any],
    kind: str,
    item_id: str,
) -> None:
    summary["attempted"] += 1
    try:
        await sender.send_alert(
            device_token=device_token,
            title=title,
            body=body,
            user_info=user_info,
        )
        summary["sent"] += 1
    except Exception as exc:  # APNs rejects individual tokens independently.
        summary["failed"] += 1
        error: dict[str, Any] = {
            "deviceTokenSuffix": device_token[-5:],
            "kind": kind,
            "id": item_id,
            "error": str(exc),
            "errorType": type(exc).__name__,
        }
        status_code = getattr(exc, "status_code", None)
        if status_code is not None:
            error["statusCode"] = status_code
        response_body = getattr(exc, "response_body", None)
        if response_body:
            error["responseBody"] = response_body
        summary["errors"].append(error)


def delivery_status(summary: dict[str, Any]) -> str:
    if summary.get("attempted", 0) == 0:
        return "skipped"
    if summary.get("failed", 0) == 0:
        return "sent"
    if summary.get("sent", 0) > 0:
        return "partial"
    return "failed"


def notifier_status(
    *,
    storage_dir: Path,
    manifest_url: str,
    public_notifier_url: str,
    apns_configured: bool,
    apns_environment: str,
    daily_weather: dict[str, Any] | None = None,
    daily_humor: dict[str, Any] | None = None,
) -> dict[str, Any]:
    devices = load_json(storage_dir / "devices.json", {})
    last_webhook = load_json(storage_dir / "last-webhook.json", None)
    last_apns_delivery = load_json(storage_dir / "last-apns-delivery.json", None)
    last_device_registration = load_json(storage_dir / "last-device-registration.json", None)

    return {
        "status": "ok",
        "manifestURL": manifest_url,
        "publicNotifierURL": normalized_public_notifier_url(public_notifier_url),
        "registeredDevices": len(devices) if isinstance(devices, dict) else 0,
        "apnsConfigured": apns_configured,
        "apnsEnvironment": apns_environment,
        "lastWebhook": last_webhook,
        "lastApnsDelivery": last_apns_delivery,
        "lastDeviceRegistration": last_device_registration,
        "dailyWeather": daily_weather,
        "dailyHumor": daily_humor,
    }


def load_json(path: Path, default: Any) -> Any:
    if not path.exists():
        return default
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def save_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp_path = path.with_suffix(path.suffix + ".tmp")
    with tmp_path.open("w", encoding="utf-8") as handle:
        json.dump(value, handle, ensure_ascii=False, indent=2)
        handle.write("\n")
    tmp_path.replace(path)
