from __future__ import annotations

import hashlib
import hmac
import importlib.util
import asyncio
import json
import sys
from pathlib import Path


def load_core():
    module_path = (
        Path(__file__).resolve().parents[1]
        / "backend"
        / "pavbot-notifier"
        / "pavbot_notifier"
        / "core.py"
    )
    spec = importlib.util.spec_from_file_location("pavbot_notifier_core", module_path)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def test_compute_manifest_changes_detects_new_artifacts_and_automations():
    core = load_core()
    previous = {
        "automations": [{"id": "research", "enabled": True}],
        "artifacts": [{"id": "run-1"}],
    }
    current = {
        "automations": [
            {"id": "research", "enabled": True},
            {"id": "mobile", "enabled": True, "name": "Mobile"},
        ],
        "artifacts": [
            {"id": "run-2", "date": "2026-06-23", "time": "10:15", "path": "research/mobile/runs/2026-06-23.md"},
            {"id": "run-1", "date": "2026-06-22", "path": "research/tech/runs/2026-06-22.md"},
        ],
    }

    changes = core.compute_manifest_changes(previous, current)

    assert [item["id"] for item in changes.artifacts] == ["run-2"]
    assert [item["id"] for item in changes.automations] == ["mobile"]


def test_compute_manifest_changes_does_not_notify_on_initial_snapshot():
    core = load_core()

    changes = core.compute_manifest_changes(None, {"automations": [{"id": "a"}], "artifacts": [{"id": "x"}]})

    assert changes.artifacts == []
    assert changes.automations == []
    assert changes.has_changes is False


def test_verify_github_signature_accepts_valid_sha256_signature():
    core = load_core()
    secret = "top-secret"
    body = b'{"ref":"refs/heads/main"}'
    digest = hmac.new(secret.encode("utf-8"), body, hashlib.sha256).hexdigest()

    assert core.verify_github_signature(secret, body, f"sha256={digest}") is True
    assert core.verify_github_signature(secret, body, "sha256=bad") is False


def test_notifier_status_reports_devices_public_url_and_last_webhook(tmp_path):
    core = load_core()
    (tmp_path / "devices.json").write_text(
        json.dumps(
            {
                "token-a": {"manifestURL": "https://raw.githubusercontent.com/example/pavbot/main/public/pavbot-manifest.json"},
                "token-b": {"manifestURL": "https://raw.githubusercontent.com/example/pavbot/main/public/pavbot-manifest.json"},
            }
        ),
        encoding="utf-8",
    )
    (tmp_path / "last-webhook.json").write_text(
        json.dumps({"event": "push", "status": "processed", "newArtifacts": 1, "newAutomations": 0}),
        encoding="utf-8",
    )

    status = core.notifier_status(
        storage_dir=tmp_path,
        manifest_url="https://raw.githubusercontent.com/example/pavbot/main/public/pavbot-manifest.json",
        public_notifier_url="https://notify.example.com/",
        apns_configured=True,
    )

    assert status["status"] == "ok"
    assert status["registeredDevices"] == 2
    assert status["publicNotifierURL"] == "https://notify.example.com"
    assert status["manifestURL"].endswith("/public/pavbot-manifest.json")
    assert status["apnsConfigured"] is True
    assert status["lastWebhook"]["newArtifacts"] == 1


def test_normalized_public_notifier_url_trims_whitespace_and_slashes():
    core = load_core()

    assert core.normalized_public_notifier_url(" https://notify.example.com/// ") == "https://notify.example.com"


def test_send_apns_change_notifications_continues_after_device_failure():
    core = load_core()

    class FakeSender:
        def __init__(self):
            self.calls = []

        async def send_alert(self, device_token, title, body, user_info):
            self.calls.append(
                {
                    "deviceToken": device_token,
                    "title": title,
                    "body": body,
                    "userInfo": user_info,
                }
            )
            if device_token == "bad-token":
                raise RuntimeError("Unregistered")

    sender = FakeSender()
    devices = {
        "bad-token": {
            "manifestURL": "https://raw.githubusercontent.com/example/pavbot/main/public/pavbot-manifest.json"
        },
        "good-token": {
            "manifestURL": "https://raw.githubusercontent.com/example/pavbot/main/public/pavbot-manifest.json"
        },
        "other-manifest-token": {
            "manifestURL": "https://raw.githubusercontent.com/example/other/main/public/pavbot-manifest.json"
        },
    }
    artifacts = [
        {
            "id": "research/tech-news/runs/2026-06-22.md",
            "type": "run",
            "topic": "tech-news",
            "title": "Daily Research Report",
            "path": "research/tech-news/runs/2026-06-22.md",
        }
    ]

    summary = asyncio.run(
        core.send_apns_change_notifications(
            devices=devices,
            artifacts=artifacts,
            automations=[],
            manifest_url_value="https://raw.githubusercontent.com/example/pavbot/main/public/pavbot-manifest.json",
            sender=sender,
        )
    )

    assert [call["deviceToken"] for call in sender.calls] == ["bad-token", "good-token"]
    assert summary["attempted"] == 2
    assert summary["sent"] == 1
    assert summary["failed"] == 1
    assert summary["skippedDevices"] == 1
    assert summary["errors"] == [
        {
            "deviceTokenSuffix": "token",
            "kind": "artifact",
            "id": "research/tech-news/runs/2026-06-22.md",
            "error": "Unregistered",
        }
    ]
    assert sender.calls[1]["userInfo"]["artifactID"] == "research/tech-news/runs/2026-06-22.md"
