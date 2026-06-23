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
    }

    for device_token, registration in devices.items():
        if not isinstance(registration, dict):
            summary["skippedDevices"] += 1
            continue
        if registration.get("manifestURL") and registration.get("manifestURL") != manifest_url_value:
            summary["skippedDevices"] += 1
            continue

        for artifact in artifacts[:8]:
            await send_apns_alert_safely(
                sender=sender,
                device_token=device_token,
                title=f"New {artifact.get('type', 'artifact')}",
                body=f"{artifact.get('topic', 'Pavbot')} · {artifact.get('title', artifact.get('path', 'New file'))}",
                user_info={
                    "artifactID": artifact.get("id", ""),
                    "artifactPath": artifact.get("path", ""),
                    "manifestURL": manifest_url_value,
                },
                summary=summary,
                kind="artifact",
                item_id=str(artifact.get("id", "")),
            )

        for automation in automations[:8]:
            await send_apns_alert_safely(
                sender=sender,
                device_token=device_token,
                title="New automation",
                body=f"{automation.get('name', automation.get('id', 'Pavbot automation'))} · {automation.get('topicPath', '')}",
                user_info={
                    "automationID": automation.get("id", ""),
                    "manifestURL": manifest_url_value,
                },
                summary=summary,
                kind="automation",
                item_id=str(automation.get("id", "")),
            )

    return summary


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
        summary["errors"].append(
            {
                "deviceTokenSuffix": device_token[-5:],
                "kind": kind,
                "id": item_id,
                "error": str(exc),
            }
        )


def notifier_status(
    *,
    storage_dir: Path,
    manifest_url: str,
    public_notifier_url: str,
    apns_configured: bool,
) -> dict[str, Any]:
    devices = load_json(storage_dir / "devices.json", {})
    last_webhook = load_json(storage_dir / "last-webhook.json", None)

    return {
        "status": "ok",
        "manifestURL": manifest_url,
        "publicNotifierURL": normalized_public_notifier_url(public_notifier_url),
        "registeredDevices": len(devices) if isinstance(devices, dict) else 0,
        "apnsConfigured": apns_configured,
        "lastWebhook": last_webhook,
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
