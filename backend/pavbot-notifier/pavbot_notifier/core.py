from __future__ import annotations

import hashlib
import hmac
import asyncio
import inspect
import json
import urllib.request
from dataclasses import dataclass
from pathlib import Path
from typing import Any


PULSE_NEWS_TOPIC = "puls-dnia-news"
PULSE_NEWS_TYPE = "pulseNewsData"
PULSE_NEWS_NOTIFICATION_TITLE = "Nowe tematy - Puls dnia"
PULSE_NEWS_FALLBACK_BODY = "Nowy zestaw tematów jest gotowy. Otwórz Puls dnia i sprawdź najnowsze karty."
PULSE_NEWS_CTA = "Otwórz Puls dnia i przewiń najnowsze tematy."
PULSE_NEWS_BODY_LIMIT = 160


@dataclass(frozen=True)
class ManifestChanges:
    artifacts: list[dict[str, Any]]
    automations: list[dict[str, Any]]

    @property
    def has_changes(self) -> bool:
        return bool(self.artifacts or self.automations)


@dataclass(frozen=True)
class PublicArtifactReadiness:
    status: str
    attempts: int
    manifest_url: str
    artifact_url: str = ""
    artifact_path: str = ""
    error: str = ""
    pulse_news_digest: dict[str, Any] | None = None

    def as_status(self) -> dict[str, Any]:
        status = {
            "status": self.status,
            "attempts": self.attempts,
            "manifestURL": self.manifest_url,
        }
        if self.artifact_url:
            status["artifactURL"] = self.artifact_url
        if self.artifact_path:
            status["artifactPath"] = self.artifact_path
        if self.error:
            status["error"] = self.error
        return status


class PublicArtifactNotReady(RuntimeError):
    def __init__(self, message: str, *, artifact_url: str = "", artifact_path: str = "") -> None:
        super().__init__(message)
        self.artifact_url = artifact_url
        self.artifact_path = artifact_path


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
    fetch_json: Any | None = None,
    pulse_news_digest: dict[str, Any] | None = None,
) -> dict[str, Any]:
    summary: dict[str, Any] = {
        "attempted": 0,
        "sent": 0,
        "failed": 0,
        "skippedDevices": 0,
        "errors": [],
        "status": "skipped",
    }

    sender_configured = getattr(getattr(sender, "config", None), "is_configured", True)
    summary["apnsConfigured"] = bool(sender_configured)
    if not sender_configured:
        summary["skippedReason"] = "APNs is not configured"
        return summary

    pulse_digest = pulse_news_digest
    if pulse_news_data_artifacts(artifacts) and pulse_digest is None:
        try:
            pulse_digest = await resolve_pulse_news_digest(
                artifacts,
                fetch_json=fetch_json or fetch_remote_json,
            )
        except PublicArtifactNotReady as exc:
            summary["status"] = "not_ready"
            summary["skippedReason"] = "pulseNewsData is not publicly readable"
            summary["publicReadiness"] = {
                "status": "not_ready",
                "artifactURL": exc.artifact_url,
                "artifactPath": exc.artifact_path,
                "error": str(exc),
            }
            return summary
    notification = build_change_notification(
        artifacts=artifacts,
        automations=automations,
        manifest_url_value=manifest_url_value,
        pulse_news_digest=pulse_digest,
    )
    if notification is None:
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
    pulse_news_digest: dict[str, Any] | None = None,
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

    pulse_artifacts = pulse_news_data_artifacts(artifacts)
    if pulse_artifacts:
        user_info["notificationKind"] = "pulseNews"
        user_info["artifactTopic"] = PULSE_NEWS_TOPIC
        selected_article = selected_pulse_news_article(pulse_news_digest)
        if selected_article:
            user_info["pulseArticleID"] = selected_article["id"]
            user_info["pulseArticleTitle"] = selected_article["title"]
        return {
            "title": PULSE_NEWS_NOTIFICATION_TITLE,
            "body": pulse_news_notification_body(selected_article),
            "userInfo": user_info,
            "summaryID": str(pulse_artifacts[0].get("id") or artifact_ids[0]),
        }

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


async def fetch_remote_json(url: str) -> dict[str, Any]:
    payload = await asyncio.to_thread(fetch_remote_json_sync, url)
    return payload if isinstance(payload, dict) else {}


async def fetch_remote_bytes(url: str) -> bytes:
    return await asyncio.to_thread(fetch_remote_bytes_sync, url)


def fetch_remote_json_sync(url: str) -> dict[str, Any]:
    request = urllib.request.Request(
        url,
        headers={
            "Cache-Control": "no-cache",
            "Pragma": "no-cache",
            "Accept": "application/json",
        },
    )
    with urllib.request.urlopen(request, timeout=15) as response:
        payload = json.load(response)
    return payload if isinstance(payload, dict) else {}


def fetch_remote_bytes_sync(url: str) -> bytes:
    request = urllib.request.Request(
        url,
        headers={
            "Cache-Control": "no-cache",
            "Pragma": "no-cache",
        },
    )
    with urllib.request.urlopen(request, timeout=15) as response:
        return response.read(1)


async def wait_for_public_artifacts_ready(
    *,
    artifacts: list[dict[str, Any]],
    manifest_url_value: str,
    fetch_manifest_json: Any = fetch_remote_json,
    fetch_json: Any = fetch_remote_json,
    fetch_url: Any = fetch_remote_bytes,
    max_attempts: int = 4,
    delay_seconds: float = 2.0,
) -> PublicArtifactReadiness:
    attempts = max(1, max_attempts)
    last_result = PublicArtifactReadiness(
        status="not_ready",
        attempts=0,
        manifest_url=manifest_url_value,
        error="public artifacts were not checked",
    )

    for attempt in range(1, attempts + 1):
        result = await check_public_artifacts_ready(
            artifacts=artifacts,
            manifest_url_value=manifest_url_value,
            fetch_manifest_json=fetch_manifest_json,
            fetch_json=fetch_json,
            fetch_url=fetch_url,
            attempt=attempt,
        )
        if result.status == "ready":
            return result
        last_result = result
        if attempt < attempts and delay_seconds > 0:
            await asyncio.sleep(delay_seconds)

    return PublicArtifactReadiness(
        status="timeout",
        attempts=last_result.attempts,
        manifest_url=last_result.manifest_url,
        artifact_url=last_result.artifact_url,
        artifact_path=last_result.artifact_path,
        error=last_result.error,
    )


async def check_public_artifacts_ready(
    *,
    artifacts: list[dict[str, Any]],
    manifest_url_value: str,
    fetch_manifest_json: Any,
    fetch_json: Any,
    fetch_url: Any,
    attempt: int,
) -> PublicArtifactReadiness:
    try:
        manifest = await maybe_await(fetch_manifest_json(manifest_url_value))
    except Exception as exc:
        return PublicArtifactReadiness(
            status="not_ready",
            attempts=attempt,
            manifest_url=manifest_url_value,
            error=f"manifest is not publicly readable: {exc}",
        )

    if not isinstance(manifest, dict):
        return PublicArtifactReadiness(
            status="not_ready",
            attempts=attempt,
            manifest_url=manifest_url_value,
            error="manifest is not a JSON object",
        )

    public_artifacts = [
        artifact
        for artifact in manifest.get("artifacts", [])
        if isinstance(artifact, dict)
    ]
    pulse_news_digest: dict[str, Any] | None = None
    last_artifact_url = ""
    last_artifact_path = ""

    for artifact in artifacts:
        public_artifact = matching_public_artifact(artifact, public_artifacts)
        if public_artifact is None:
            return PublicArtifactReadiness(
                status="not_ready",
                attempts=attempt,
                manifest_url=manifest_url_value,
                artifact_path=str(artifact.get("path") or artifact.get("id") or ""),
                error="artifact is missing from public manifest",
            )

        artifact_url = str(public_artifact.get("url") or artifact.get("url") or "").strip()
        artifact_path = str(public_artifact.get("path") or artifact.get("path") or "").strip()
        last_artifact_url = artifact_url
        last_artifact_path = artifact_path
        if not artifact_url:
            return PublicArtifactReadiness(
                status="not_ready",
                attempts=attempt,
                manifest_url=manifest_url_value,
                artifact_path=artifact_path,
                error="artifact has no public URL",
            )

        if is_pulse_news_data_artifact(public_artifact):
            try:
                payload = await maybe_await(fetch_json(artifact_url))
                validate_pulse_news_payload_ready(payload, public_artifact)
            except Exception as exc:
                return PublicArtifactReadiness(
                    status="not_ready",
                    attempts=attempt,
                    manifest_url=manifest_url_value,
                    artifact_url=artifact_url,
                    artifact_path=artifact_path,
                    error=f"pulseNewsData is not publicly readable: {exc}",
                )
            pulse_news_digest = payload
        else:
            try:
                await maybe_await(fetch_url(artifact_url))
            except Exception as exc:
                return PublicArtifactReadiness(
                    status="not_ready",
                    attempts=attempt,
                    manifest_url=manifest_url_value,
                    artifact_url=artifact_url,
                    artifact_path=artifact_path,
                    error=f"artifact is not publicly readable: {exc}",
                )

    return PublicArtifactReadiness(
        status="ready",
        attempts=attempt,
        manifest_url=manifest_url_value,
        artifact_url=last_artifact_url,
        artifact_path=last_artifact_path,
        pulse_news_digest=pulse_news_digest,
    )


async def maybe_await(value: Any) -> Any:
    if inspect.isawaitable(value):
        return await value
    return value


def matching_public_artifact(
    artifact: dict[str, Any],
    public_artifacts: list[dict[str, Any]],
) -> dict[str, Any] | None:
    artifact_id = artifact.get("id")
    artifact_path = artifact.get("path")
    for public_artifact in public_artifacts:
        if artifact_id and public_artifact.get("id") == artifact_id:
            return public_artifact
        if artifact_path and public_artifact.get("path") == artifact_path:
            return public_artifact
    return None


def validate_pulse_news_payload_ready(payload: Any, artifact: dict[str, Any]) -> None:
    if not isinstance(payload, dict):
        raise PublicArtifactNotReady("pulseNewsData JSON is not an object")
    if artifact.get("date") and payload.get("runDate") != artifact.get("date"):
        raise PublicArtifactNotReady("pulseNewsData runDate does not match manifest artifact date")
    if artifact.get("time") and payload.get("runTime") != artifact.get("time"):
        raise PublicArtifactNotReady("pulseNewsData runTime does not match manifest artifact time")
    items = payload.get("items")
    if not isinstance(items, list) or not items:
        raise PublicArtifactNotReady("pulseNewsData items are missing")


async def resolve_pulse_news_digest(
    artifacts: list[dict[str, Any]],
    *,
    fetch_json: Any,
) -> dict[str, Any] | None:
    for artifact in pulse_news_data_artifacts(artifacts):
        url = str(artifact.get("url") or "").strip()
        if not url:
            raise PublicArtifactNotReady(
                "pulseNewsData artifact has no public URL",
                artifact_path=str(artifact.get("path") or artifact.get("id") or ""),
            )
        try:
            payload = await maybe_await(fetch_json(url))
            validate_pulse_news_payload_ready(payload, artifact)
        except Exception as exc:
            raise PublicArtifactNotReady(
                "pulseNewsData is not publicly readable",
                artifact_url=url,
                artifact_path=str(artifact.get("path") or artifact.get("id") or ""),
            ) from exc
        return payload
    return None


def pulse_news_data_artifacts(artifacts: list[dict[str, Any]]) -> list[dict[str, Any]]:
    return [
        artifact
        for artifact in artifacts
        if artifact.get("topic") == PULSE_NEWS_TOPIC and artifact.get("type") == PULSE_NEWS_TYPE
    ]


def is_pulse_news_data_artifact(artifact: dict[str, Any]) -> bool:
    return artifact.get("topic") == PULSE_NEWS_TOPIC and artifact.get("type") == PULSE_NEWS_TYPE


def selected_pulse_news_article(payload: dict[str, Any] | None) -> dict[str, str] | None:
    if not isinstance(payload, dict):
        return None
    items = payload.get("items")
    if not isinstance(items, list):
        return None

    candidates = [normalized_pulse_news_article(item) for item in items]
    candidates = [item for item in candidates if item is not None]
    if not candidates:
        return None

    high_priority = [
        item
        for item in candidates
        if item["priority"].strip().lower() == "high"
    ]
    return (high_priority or candidates)[0]


def normalized_pulse_news_article(value: Any) -> dict[str, str] | None:
    if not isinstance(value, dict):
        return None
    title = clean_notification_text(value.get("title"))
    lead = clean_notification_text(value.get("lead"))
    if not title or not lead:
        return None
    article_id = clean_notification_text(value.get("id")) or title
    priority = clean_notification_text(value.get("priority"))
    return {
        "id": article_id,
        "title": title,
        "lead": lead,
        "priority": priority,
    }


def clean_notification_text(value: Any) -> str:
    if not isinstance(value, str):
        return ""
    return " ".join(value.split()).strip()


def pulse_news_notification_body(article: dict[str, str] | None) -> str:
    if not article:
        return PULSE_NEWS_FALLBACK_BODY
    title = fit_text(
        article["title"],
        PULSE_NEWS_BODY_LIMIT - len('Warto sprawdzić: "". ') - len(PULSE_NEWS_CTA),
    )
    return f'Warto sprawdzić: "{title}". {PULSE_NEWS_CTA}'


def fit_text(value: str, limit: int) -> str:
    value = clean_notification_text(value)
    if limit <= 3:
        return value[:limit]
    if len(value) <= limit:
        return value
    return value[: limit - 3].rstrip(" ,.;:-") + "..."


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
    last_public_readiness = load_json(storage_dir / "last-public-readiness.json", None)

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
        "lastPublicReadiness": last_public_readiness,
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
