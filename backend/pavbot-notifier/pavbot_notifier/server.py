from __future__ import annotations

import asyncio
import os
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import httpx
from fastapi import FastAPI, Header, HTTPException, Request
from pydantic import BaseModel, Field

from .apns import APNSConfig, APNSSender, read_private_key
from .core import (
    app_connection_defaults,
    compute_manifest_changes,
    load_json,
    normalized_public_notifier_url,
    notifier_status,
    save_json,
    send_apns_change_notifications,
    verify_github_signature,
    wait_for_public_artifacts_ready,
)
from .daily_weather import (
    DailyWeatherConfig,
    DailyWeatherRefreshLocked,
    daily_weather_scheduler_loop,
    daily_weather_status,
    hourly_weather_scheduler_loop,
    latest_daily_weather_report,
    refresh_daily_weather_report,
)
from .daily_humor import (
    DailyHumorConfig,
    daily_humor_status,
    humor_ingest_token_is_valid,
    humor_scheduler_loop,
    latest_humor_digest,
    save_external_humor_digest,
)


class DeviceRegistration(BaseModel):
    device_token: str = Field(alias="deviceToken")
    platform: str = "ios"
    bundle_id: str = Field(alias="bundleId")
    manifest_url: str = Field(alias="manifestURL")
    app_version: str = Field(default="", alias="appVersion")
    build_number: str = Field(default="", alias="buildNumber")
    daily_weather_enabled: bool = Field(default=False, alias="dailyWeatherEnabled")


class HumorDigestCommentHighlightPayload(BaseModel):
    id: str
    summary: str
    originalBody: str | None = None
    explanation: str
    score: int | None = None


class HumorDigestItemPayload(BaseModel):
    id: str
    title: str
    caption: str
    sourceName: str
    sourceURL: str
    imageURL: str | None = None
    score: int | None = None
    comments: int | None = None
    tags: list[str] = Field(default_factory=list)
    categoryLabel: str | None = None
    postText: str | None = None
    whyFunny: str | None = None
    commentHighlights: list[HumorDigestCommentHighlightPayload] = Field(default_factory=list)


class HumorDigestPayload(BaseModel):
    id: str
    title: str
    summary: str
    generatedAt: str
    displayTime: str
    nextRefreshAt: str | None = None
    refreshIntervalHours: int
    items: list[HumorDigestItemPayload]
    source: str


def humor_digest_original_body_errors(digest: HumorDigestPayload) -> list[str]:
    errors: list[str] = []
    for item_index, item in enumerate(digest.items):
        for highlight_index, highlight in enumerate(item.commentHighlights):
            if not (highlight.originalBody or "").strip():
                errors.append(f"items[{item_index}].commentHighlights[{highlight_index}].originalBody is required")
    return errors


def data_dir() -> Path:
    return Path(os.environ.get("PAVBOT_NOTIFIER_DATA_DIR", "/data"))


def manifest_url() -> str:
    value = os.environ.get("PAVBOT_MANIFEST_URL", "").strip()
    if not value:
        raise HTTPException(status_code=500, detail="PAVBOT_MANIFEST_URL is not configured")
    return value


def public_notifier_url() -> str:
    return normalized_public_notifier_url(os.environ.get("PAVBOT_PUBLIC_NOTIFIER_URL", ""))


def public_readiness_attempts() -> int:
    try:
        return max(1, int(os.environ.get("PAVBOT_PUBLIC_READINESS_ATTEMPTS", "4")))
    except ValueError:
        return 4


def public_readiness_delay_seconds() -> float:
    try:
        return max(0.0, float(os.environ.get("PAVBOT_PUBLIC_READINESS_DELAY_SECONDS", "2")))
    except ValueError:
        return 2.0


def apns_sender() -> APNSSender:
    private_key = read_private_key(
        os.environ.get("APNS_PRIVATE_KEY", ""),
        os.environ.get("APNS_PRIVATE_KEY_PATH", ""),
    )
    return APNSSender(
        APNSConfig(
            team_id=os.environ.get("APNS_TEAM_ID", ""),
            key_id=os.environ.get("APNS_KEY_ID", ""),
            bundle_id=os.environ.get("APNS_BUNDLE_ID", "com.paweltanski.pavbotviewer"),
            private_key=private_key,
            environment=os.environ.get("APNS_ENV", "sandbox"),
        )
    )


app = FastAPI(title="Pavbot iOS Live Notifier")
daily_weather_task: asyncio.Task[Any] | None = None
hourly_weather_task: asyncio.Task[Any] | None = None
humor_task: asyncio.Task[Any] | None = None


def daily_weather_config() -> DailyWeatherConfig:
    return DailyWeatherConfig.from_env()


def daily_humor_config() -> DailyHumorConfig:
    return DailyHumorConfig.from_env()


def daily_weather_config_for_location(
    *,
    latitude: float | None = None,
    longitude: float | None = None,
    city: str | None = None,
) -> DailyWeatherConfig:
    return daily_weather_config().with_location(
        latitude=latitude,
        longitude=longitude,
        city=city,
    )


@app.on_event("startup")
async def start_daily_weather_scheduler() -> None:
    global daily_weather_task, hourly_weather_task, humor_task
    if daily_weather_task is not None and not daily_weather_task.done():
        daily_running = True
    else:
        daily_running = False
    if not daily_running:
        daily_weather_task = asyncio.create_task(
            daily_weather_scheduler_loop(
                config_factory=daily_weather_config,
                storage_dir=data_dir(),
                sender_factory=apns_sender,
            )
        )
    if hourly_weather_task is None or hourly_weather_task.done():
        hourly_weather_task = asyncio.create_task(
            hourly_weather_scheduler_loop(
                config_factory=daily_weather_config,
                storage_dir=data_dir(),
            )
        )
    if humor_task is None or humor_task.done():
        humor_task = asyncio.create_task(
            humor_scheduler_loop(
                config_factory=daily_humor_config,
                storage_dir=data_dir(),
            )
        )


@app.on_event("shutdown")
async def stop_daily_weather_scheduler() -> None:
    global daily_weather_task, hourly_weather_task, humor_task
    tasks = [task for task in [daily_weather_task, hourly_weather_task, humor_task] if task is not None]
    for task in tasks:
        task.cancel()
    for task in tasks:
        try:
            await task
        except asyncio.CancelledError:
            pass
    daily_weather_task = None
    hourly_weather_task = None
    humor_task = None


@app.get("/healthz")
async def healthz() -> dict[str, str]:
    return {"status": "ok"}


@app.get("/status")
async def status() -> dict[str, Any]:
    return notifier_status(
        storage_dir=data_dir(),
        manifest_url=manifest_url(),
        public_notifier_url=public_notifier_url(),
        apns_configured=apns_configured_from_env(),
        apns_environment=os.environ.get("APNS_ENV", "sandbox"),
        daily_weather=daily_weather_status(storage_dir=data_dir(), config=daily_weather_config()),
        daily_humor=daily_humor_status(storage_dir=data_dir(), config=daily_humor_config()),
    )


@app.get("/v1/app/defaults")
async def app_defaults_endpoint() -> dict[str, Any]:
    try:
        return app_connection_defaults(
            manifest_url=os.environ.get("PAVBOT_MANIFEST_URL", ""),
            public_notifier_url=os.environ.get("PAVBOT_PUBLIC_NOTIFIER_URL", ""),
        )
    except ValueError as exc:
        raise HTTPException(status_code=500, detail=str(exc)) from exc


@app.post("/v1/devices")
async def register_device(registration: DeviceRegistration) -> dict[str, str]:
    devices_path = data_dir() / "devices.json"
    devices = load_json(devices_path, {})
    devices[registration.device_token] = registration.model_dump(by_alias=True)
    save_json(devices_path, devices)
    save_json(
        data_dir() / "last-device-registration.json",
        {
            "registeredAt": datetime.now(timezone.utc).isoformat(),
            "status": "registered",
            "deviceTokenSuffix": registration.device_token[-5:],
            "platform": registration.platform,
            "bundleID": registration.bundle_id,
            "manifestURL": registration.manifest_url,
            "appVersion": registration.app_version,
            "buildNumber": registration.build_number,
            "dailyWeatherEnabled": registration.daily_weather_enabled,
        },
    )
    return {"status": "registered"}


@app.get("/v1/weather/daily/latest")
async def daily_weather_latest(
    lat: float | None = None,
    lon: float | None = None,
    city: str | None = None,
) -> dict[str, Any]:
    try:
        return await latest_daily_weather_report(
            config=daily_weather_config_for_location(latitude=lat, longitude=lon, city=city),
            storage_dir=data_dir(),
        )
    except httpx.HTTPError as exc:
        raise HTTPException(status_code=502, detail=f"Weather provider error: {exc}") from exc


@app.post("/v1/weather/daily/refresh")
async def daily_weather_refresh(
    lat: float | None = None,
    lon: float | None = None,
    city: str | None = None,
) -> dict[str, Any]:
    try:
        result = await refresh_daily_weather_report(
            config=daily_weather_config_for_location(latitude=lat, longitude=lon, city=city),
            storage_dir=data_dir(),
        )
        return result["report"]
    except DailyWeatherRefreshLocked as exc:
        raise HTTPException(
            status_code=429,
            detail={
                "message": "Weather refresh is locked until the next hour.",
                "retryAt": exc.retry_at.isoformat(),
                "lastReport": exc.last_report,
            },
        ) from exc
    except httpx.HTTPError as exc:
        raise HTTPException(status_code=502, detail=f"Weather provider error: {exc}") from exc


@app.get("/v1/humor/latest")
async def humor_latest() -> dict[str, Any]:
    try:
        return await latest_humor_digest(config=daily_humor_config(), storage_dir=data_dir())
    except httpx.HTTPError as exc:
        raise HTTPException(status_code=502, detail=f"Humor provider error: {exc}") from exc


@app.post("/v1/humor/digest")
async def humor_digest_ingest(
    digest: HumorDigestPayload,
    authorization: str | None = Header(default=None),
) -> dict[str, Any]:
    expected_token = os.environ.get("PAVBOT_HUMOR_INGEST_TOKEN", "")
    if not humor_ingest_token_is_valid(authorization, expected_token=expected_token):
        raise HTTPException(status_code=401, detail="Invalid humor ingest token")
    original_body_errors = humor_digest_original_body_errors(digest)
    if original_body_errors:
        raise HTTPException(
            status_code=422,
            detail={
                "message": "Humor digest commentHighlights require originalBody",
                "errors": original_body_errors,
            },
        )
    return save_external_humor_digest(
        digest=digest.model_dump(),
        storage_dir=data_dir(),
        received_at=datetime.now(timezone.utc),
    )


@app.post("/webhooks/github")
async def github_webhook(
    request: Request,
    x_hub_signature_256: str | None = Header(default=None),
    x_github_event: str | None = Header(default=None),
) -> dict[str, Any]:
    body = await request.body()
    secret = os.environ.get("GITHUB_WEBHOOK_SECRET", "")
    if not verify_github_signature(secret, body, x_hub_signature_256):
        raise HTTPException(status_code=401, detail="Invalid GitHub webhook signature")

    if x_github_event == "ping":
        record_webhook_status(event="ping", status="pong")
        return {"status": "pong"}
    if x_github_event and x_github_event != "push":
        record_webhook_status(event=x_github_event, status="ignored")
        return {"status": "ignored", "event": x_github_event}

    current_manifest = await fetch_manifest(manifest_url())
    state_path = data_dir() / "last-manifest.json"
    previous_manifest = load_json(state_path, None)
    changes = compute_manifest_changes(previous_manifest, current_manifest)
    apns_summary: dict[str, Any] = {
        "attempted": 0,
        "sent": 0,
        "failed": 0,
        "skippedDevices": 0,
        "errors": [],
    }

    public_readiness_status: dict[str, Any] | None = None
    if changes.has_changes:
        readiness = await wait_for_public_artifacts_ready(
            artifacts=changes.artifacts,
            manifest_url_value=manifest_url(),
            fetch_manifest_json=fetch_manifest,
            max_attempts=public_readiness_attempts(),
            delay_seconds=public_readiness_delay_seconds(),
        )
        public_readiness_status = readiness.as_status()
        if readiness.status != "ready":
            apns_summary["status"] = readiness.status
            apns_summary["skippedReason"] = "public artifacts are not ready for iOS"
            save_public_readiness_status(public_readiness_status)
            record_webhook_status(
                event=x_github_event or "push",
                status=readiness.status,
                new_artifacts=len(changes.artifacts),
                new_automations=len(changes.automations),
                apns_summary=apns_summary,
            )
            return {
                "status": readiness.status,
                "newArtifacts": len(changes.artifacts),
                "newAutomations": len(changes.automations),
                "publicReadiness": public_readiness_status,
                "apns": apns_summary,
            }

        apns_summary = await send_change_notifications(
            changes.artifacts,
            changes.automations,
            current_manifest,
            pulse_news_digest=readiness.pulse_news_digest,
        )
        public_readiness_status["status"] = "sent" if apns_summary.get("sent", 0) > 0 else "ready"
        save_public_readiness_status(public_readiness_status)

    save_json(state_path, current_manifest)
    record_webhook_status(
        event=x_github_event or "push",
        status="processed",
        new_artifacts=len(changes.artifacts),
        new_automations=len(changes.automations),
        apns_summary=apns_summary,
    )
    return {
        "status": "processed",
        "newArtifacts": len(changes.artifacts),
        "newAutomations": len(changes.automations),
        "publicReadiness": public_readiness_status,
        "apns": apns_summary,
    }


async def fetch_manifest(url: str) -> dict[str, Any]:
    headers = {
        "Cache-Control": "no-cache",
        "Pragma": "no-cache",
    }
    async with httpx.AsyncClient(timeout=20) as client:
        response = await client.get(url, headers=headers)
        response.raise_for_status()
        return response.json()


async def send_change_notifications(
    artifacts: list[dict[str, Any]],
    automations: list[dict[str, Any]],
    manifest: dict[str, Any],
    pulse_news_digest: dict[str, Any] | None = None,
) -> dict[str, Any]:
    devices = load_json(data_dir() / "devices.json", {})
    sender = apns_sender()
    manifest_url_value = os.environ.get("PAVBOT_MANIFEST_URL", "")
    summary = await send_apns_change_notifications(
        devices=devices,
        artifacts=artifacts,
        automations=automations,
        manifest_url_value=manifest_url_value,
        sender=sender,
        pulse_news_digest=pulse_news_digest,
    )
    save_json(
        data_dir() / "last-apns-delivery.json",
        {
            "recordedAt": datetime.now(timezone.utc).isoformat(),
            **summary,
        },
    )
    return summary


def save_public_readiness_status(status: dict[str, Any]) -> None:
    save_json(
        data_dir() / "last-public-readiness.json",
        {
            "recordedAt": datetime.now(timezone.utc).isoformat(),
            **status,
        },
    )


def record_webhook_status(
    *,
    event: str,
    status: str,
    new_artifacts: int = 0,
    new_automations: int = 0,
    apns_summary: dict[str, Any] | None = None,
) -> None:
    save_json(
        data_dir() / "last-webhook.json",
        {
            "receivedAt": datetime.now(timezone.utc).isoformat(),
            "event": event,
            "status": status,
            "newArtifacts": new_artifacts,
            "newAutomations": new_automations,
            "apnsAttempted": (apns_summary or {}).get("attempted", 0),
            "apnsSent": (apns_summary or {}).get("sent", 0),
            "apnsFailed": (apns_summary or {}).get("failed", 0),
            "apnsSkippedDevices": (apns_summary or {}).get("skippedDevices", 0),
            "apnsErrors": (apns_summary or {}).get("errors", []),
        },
    )


def apns_configured_from_env() -> bool:
    private_key = os.environ.get("APNS_PRIVATE_KEY", "")
    private_key_path = os.environ.get("APNS_PRIVATE_KEY_PATH", "")
    has_private_key = bool(private_key) or bool(private_key_path and Path(private_key_path).exists())
    return all(
        [
            os.environ.get("APNS_TEAM_ID", ""),
            os.environ.get("APNS_KEY_ID", ""),
            os.environ.get("APNS_BUNDLE_ID", "com.paweltanski.pavbotviewer"),
            has_private_key,
        ]
    )
