from __future__ import annotations

import os
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import httpx
from fastapi import FastAPI, Header, HTTPException, Request
from pydantic import BaseModel, Field

from .apns import APNSConfig, APNSSender, read_private_key
from .core import (
    compute_manifest_changes,
    load_json,
    normalized_public_notifier_url,
    notifier_status,
    save_json,
    send_apns_change_notifications,
    verify_github_signature,
)


class DeviceRegistration(BaseModel):
    device_token: str = Field(alias="deviceToken")
    platform: str = "ios"
    bundle_id: str = Field(alias="bundleId")
    manifest_url: str = Field(alias="manifestURL")
    app_version: str = Field(default="", alias="appVersion")
    build_number: str = Field(default="", alias="buildNumber")


def data_dir() -> Path:
    return Path(os.environ.get("PAVBOT_NOTIFIER_DATA_DIR", "/data"))


def manifest_url() -> str:
    value = os.environ.get("PAVBOT_MANIFEST_URL", "").strip()
    if not value:
        raise HTTPException(status_code=500, detail="PAVBOT_MANIFEST_URL is not configured")
    return value


def public_notifier_url() -> str:
    return normalized_public_notifier_url(os.environ.get("PAVBOT_PUBLIC_NOTIFIER_URL", ""))


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
    )


@app.post("/v1/devices")
async def register_device(registration: DeviceRegistration) -> dict[str, str]:
    devices_path = data_dir() / "devices.json"
    devices = load_json(devices_path, {})
    devices[registration.device_token] = registration.model_dump(by_alias=True)
    save_json(devices_path, devices)
    return {"status": "registered"}


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

    if changes.has_changes:
        apns_summary = await send_change_notifications(changes.artifacts, changes.automations, current_manifest)

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
) -> dict[str, Any]:
    devices = load_json(data_dir() / "devices.json", {})
    sender = apns_sender()
    manifest_url_value = os.environ.get("PAVBOT_MANIFEST_URL", "")
    return await send_apns_change_notifications(
        devices=devices,
        artifacts=artifacts,
        automations=automations,
        manifest_url_value=manifest_url_value,
        sender=sender,
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
