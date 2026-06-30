from __future__ import annotations

import hashlib
import hmac
import importlib.util
import asyncio
import ast
import json
import sys
from pathlib import Path
from types import SimpleNamespace

import pytest


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


def load_apns():
    module_path = (
        Path(__file__).resolve().parents[1]
        / "backend"
        / "pavbot-notifier"
        / "pavbot_notifier"
        / "apns.py"
    )
    spec = importlib.util.spec_from_file_location("pavbot_notifier_apns", module_path)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def load_daily_weather():
    package_root = Path(__file__).resolve().parents[1] / "backend" / "pavbot-notifier"
    if str(package_root) not in sys.path:
        sys.path.insert(0, str(package_root))
    return importlib.import_module("pavbot_notifier.daily_weather")


def load_daily_humor():
    package_root = Path(__file__).resolve().parents[1] / "backend" / "pavbot-notifier"
    if str(package_root) not in sys.path:
        sys.path.insert(0, str(package_root))
    return importlib.import_module("pavbot_notifier.daily_humor")


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
    (tmp_path / "last-apns-delivery.json").write_text(
        json.dumps({"attempted": 2, "sent": 1, "failed": 1, "status": "partial"}),
        encoding="utf-8",
    )
    (tmp_path / "last-device-registration.json").write_text(
        json.dumps({"status": "registered", "deviceTokenSuffix": "ken-a"}),
        encoding="utf-8",
    )

    status = core.notifier_status(
        storage_dir=tmp_path,
        manifest_url="https://raw.githubusercontent.com/example/pavbot/main/public/pavbot-manifest.json",
        public_notifier_url="https://notify.example.com/",
        apns_configured=True,
        apns_environment="sandbox",
    )

    assert status["status"] == "ok"
    assert status["registeredDevices"] == 2
    assert status["publicNotifierURL"] == "https://notify.example.com"
    assert status["manifestURL"].endswith("/public/pavbot-manifest.json")
    assert status["apnsConfigured"] is True
    assert status["apnsEnvironment"] == "sandbox"
    assert status["lastWebhook"]["newArtifacts"] == 1
    assert status["lastApnsDelivery"]["status"] == "partial"
    assert status["lastDeviceRegistration"]["status"] == "registered"


def test_normalized_public_notifier_url_trims_whitespace_and_slashes():
    core = load_core()

    assert core.normalized_public_notifier_url(" https://notify.example.com/// ") == "https://notify.example.com"


def test_app_connection_defaults_returns_only_public_links():
    core = load_core()

    defaults = core.app_connection_defaults(
        manifest_url=" https://raw.githubusercontent.com/example/pavbot/main/public/pavbot-manifest.json ",
        public_notifier_url=" https://notify.example.com/ ",
    )

    assert defaults == {
        "schemaVersion": 1,
        "manifestURL": "https://raw.githubusercontent.com/example/pavbot/main/public/pavbot-manifest.json",
        "notificationServerURL": "https://notify.example.com",
        "statusURL": "https://notify.example.com/status",
    }
    assert "APNS" not in json.dumps(defaults)
    assert "SECRET" not in json.dumps(defaults)


def test_app_connection_defaults_requires_public_https_urls():
    core = load_core()

    with pytest.raises(ValueError, match="PAVBOT_MANIFEST_URL"):
        core.app_connection_defaults(
            manifest_url="",
            public_notifier_url="https://notify.example.com",
        )
    with pytest.raises(ValueError, match="PAVBOT_PUBLIC_NOTIFIER_URL"):
        core.app_connection_defaults(
            manifest_url="https://raw.githubusercontent.com/example/pavbot/main/public/pavbot-manifest.json",
            public_notifier_url="",
        )
    with pytest.raises(ValueError, match="HTTPS JSON"):
        core.app_connection_defaults(
            manifest_url="http://example.com/manifest.txt",
            public_notifier_url="https://notify.example.com",
        )
    with pytest.raises(ValueError, match="HTTPS URL"):
        core.app_connection_defaults(
            manifest_url="https://raw.githubusercontent.com/example/pavbot/main/public/pavbot-manifest.json",
            public_notifier_url="http://localhost:8080",
        )


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
    assert summary["errors"][0]["deviceTokenSuffix"] == "token"
    assert summary["errors"][0]["kind"] == "summary"
    assert summary["errors"][0]["id"] == "research/tech-news/runs/2026-06-22.md"
    assert summary["errors"][0]["error"] == "Unregistered"
    assert summary["errors"][0]["errorType"] == "RuntimeError"
    assert sender.calls[1]["userInfo"]["artifactIDs"] == ["research/tech-news/runs/2026-06-22.md"]
    assert sender.calls[1]["userInfo"]["artifactTopic"] == "tech-news"


def test_apns_sender_raises_when_apns_is_not_configured():
    apns = load_apns()
    sender = apns.APNSSender(
        apns.APNSConfig(
            team_id="",
            key_id="",
            bundle_id="com.paweltanski.pavbotviewer",
            private_key="",
            environment="sandbox",
        )
    )

    with pytest.raises(apns.APNSConfigurationError, match="APNs is not configured"):
        asyncio.run(
            sender.send_alert(
                device_token="device-token",
                title="Pavbot",
                body="New file",
                user_info={},
            )
        )


def test_send_apns_change_notifications_skips_when_sender_is_not_configured():
    core = load_core()

    class FakeConfig:
        is_configured = False

    class FakeSender:
        config = FakeConfig()

        async def send_alert(self, device_token, title, body, user_info):
            raise AssertionError("send_alert should not be called without APNs configuration")

    summary = asyncio.run(
        core.send_apns_change_notifications(
            devices={
                "good-token": {
                    "manifestURL": "https://raw.githubusercontent.com/example/pavbot/main/public/pavbot-manifest.json"
                }
            },
            artifacts=[
                {
                    "id": "research/mobile/runs/2026-06-23.md",
                    "type": "run",
                    "topic": "mobile",
                    "title": "Mobile brief",
                    "path": "research/mobile/runs/2026-06-23.md",
                    "date": "2026-06-23",
                }
            ],
            automations=[],
            manifest_url_value="https://raw.githubusercontent.com/example/pavbot/main/public/pavbot-manifest.json",
            sender=FakeSender(),
        )
    )

    assert summary["status"] == "skipped"
    assert summary["apnsConfigured"] is False
    assert summary["attempted"] == 0
    assert summary["sent"] == 0
    assert summary["skippedReason"] == "APNs is not configured"


def test_send_apns_change_notifications_sends_single_summary_per_device():
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

    sender = FakeSender()
    manifest_url = "https://raw.githubusercontent.com/example/pavbot/main/public/pavbot-manifest.json"
    artifacts = [
        {
            "id": "research/mobile/runs/2026-06-23.md",
            "type": "run",
            "topic": "mobile",
            "title": "Mobile brief",
            "path": "research/mobile/runs/2026-06-23.md",
            "date": "2026-06-23",
        },
        {
            "id": "research/mobile/pdfs/2026-06-23.pdf",
            "type": "pdf",
            "topic": "mobile",
            "title": "Mobile PDF",
            "path": "research/mobile/pdfs/2026-06-23.pdf",
            "date": "2026-06-23",
        },
    ]

    summary = asyncio.run(
        core.send_apns_change_notifications(
            devices={"good-token": {"manifestURL": manifest_url}},
            artifacts=artifacts,
            automations=[],
            manifest_url_value=manifest_url,
            sender=sender,
        )
    )

    assert summary["attempted"] == 1
    assert summary["sent"] == 1
    assert len(sender.calls) == 1
    assert sender.calls[0]["title"] == "Pavbot"
    assert sender.calls[0]["userInfo"]["artifactTopic"] == "mobile"


def test_pulse_news_notification_uses_high_priority_article_teaser():
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

    async def fetch_json(url):
        assert url == "https://raw.example.com/research/puls-dnia-news/data/2026-06-26-2109-pulse-news.json"
        return {
            "items": [
                {
                    "id": "regular-story",
                    "title": "Krótka aktualizacja z rynku energii",
                    "lead": "Ten temat jest ważny, ale nie jest najpilniejszy.",
                    "priority": "normal",
                },
                {
                    "id": "high-story",
                    "title": "Rząd pokazuje nowy pakiet dla AI w administracji",
                    "lead": "Nowe przepisy mogą przyspieszyć wdrożenia automatyzacji w sektorze publicznym.",
                    "priority": "high",
                },
            ]
        }

    sender = FakeSender()
    manifest_url = "https://raw.githubusercontent.com/example/pavbot/main/public/pavbot-manifest.json"

    summary = asyncio.run(
        core.send_apns_change_notifications(
            devices={"good-token": {"manifestURL": manifest_url}},
            artifacts=[
                {
                    "id": "research/puls-dnia-news/data/2026-06-26-2109-pulse-news.json",
                    "type": "pulseNewsData",
                    "topic": "puls-dnia-news",
                    "path": "research/puls-dnia-news/data/2026-06-26-2109-pulse-news.json",
                    "url": "https://raw.example.com/research/puls-dnia-news/data/2026-06-26-2109-pulse-news.json",
                    "date": "2026-06-26",
                    "time": "21:09",
                    "itemCount": 12,
                },
                {
                    "id": "research/puls-dnia-news/runs/2026-06-26-2109.md",
                    "type": "run",
                    "topic": "puls-dnia-news",
                    "path": "research/puls-dnia-news/runs/2026-06-26-2109.md",
                    "date": "2026-06-26",
                    "time": "21:09",
                },
            ],
            automations=[],
            manifest_url_value=manifest_url,
            sender=sender,
            fetch_json=fetch_json,
        )
    )

    assert summary["attempted"] == 1
    assert summary["sent"] == 1
    assert len(sender.calls) == 1
    call = sender.calls[0]
    assert call["title"] == "Nowe tematy - Puls dnia"
    assert 'Rząd pokazuje nowy pakiet dla AI w administracji' in call["body"]
    assert call["body"].startswith("Warto sprawdzić:")
    assert call["body"].endswith("Otwórz Puls dnia i przewiń najnowsze tematy.")
    assert len(call["body"]) <= 170
    assert call["userInfo"]["notificationKind"] == "pulseNews"
    assert call["userInfo"]["artifactTopic"] == "puls-dnia-news"
    assert call["userInfo"]["artifactDate"] == "2026-06-26"
    assert call["userInfo"]["artifactIDs"] == [
        "research/puls-dnia-news/data/2026-06-26-2109-pulse-news.json",
        "research/puls-dnia-news/runs/2026-06-26-2109.md",
    ]
    assert call["userInfo"]["pulseArticleID"] == "high-story"
    assert call["userInfo"]["pulseArticleTitle"] == "Rząd pokazuje nowy pakiet dla AI w administracji"


def test_pulse_news_notification_falls_back_when_digest_fetch_fails():
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

    async def fetch_json(url):
        raise RuntimeError("HTTP 500")

    sender = FakeSender()
    manifest_url = "https://raw.githubusercontent.com/example/pavbot/main/public/pavbot-manifest.json"

    summary = asyncio.run(
        core.send_apns_change_notifications(
            devices={"good-token": {"manifestURL": manifest_url}},
            artifacts=[
                {
                    "id": "research/puls-dnia-news/data/2026-06-26-2109-pulse-news.json",
                    "type": "pulseNewsData",
                    "topic": "puls-dnia-news",
                    "path": "research/puls-dnia-news/data/2026-06-26-2109-pulse-news.json",
                    "url": "https://raw.example.com/research/puls-dnia-news/data/2026-06-26-2109-pulse-news.json",
                    "date": "2026-06-26",
                    "time": "21:09",
                    "itemCount": 12,
                }
            ],
            automations=[],
            manifest_url_value=manifest_url,
            sender=sender,
            fetch_json=fetch_json,
        )
    )

    assert summary["attempted"] == 1
    assert summary["sent"] == 1
    assert sender.calls[0]["title"] == "Nowe tematy - Puls dnia"
    assert sender.calls[0]["body"] == "Nowy zestaw tematów jest gotowy. Otwórz Puls dnia i sprawdź najnowsze karty."
    assert sender.calls[0]["userInfo"]["notificationKind"] == "pulseNews"


def test_pulse_news_notification_builder_without_digest_uses_fallback_copy():
    core = load_core()

    notification = core.build_change_notification(
        artifacts=[
            {
                "id": "research/puls-dnia-news/data/2026-06-26-2109-pulse-news.json",
                "type": "pulseNewsData",
                "topic": "puls-dnia-news",
                "path": "research/puls-dnia-news/data/2026-06-26-2109-pulse-news.json",
                "date": "2026-06-26",
                "time": "21:09",
                "itemCount": 12,
            }
        ],
        automations=[],
        manifest_url_value="https://raw.githubusercontent.com/example/pavbot/main/public/pavbot-manifest.json",
    )

    assert notification["title"] == "Nowe tematy - Puls dnia"
    assert notification["body"] == "Nowy zestaw tematów jest gotowy. Otwórz Puls dnia i sprawdź najnowsze karty."
    assert notification["userInfo"]["artifactTopic"] == "puls-dnia-news"


def test_daily_weather_next_run_uses_warsaw_time():
    daily_weather = load_daily_weather()
    config = daily_weather.DailyWeatherConfig(
        enabled=True,
        local_time=daily_weather.time(hour=7, minute=30),
        timezone_name="Europe/Warsaw",
        city="Wrocław",
        latitude=51.1079,
        longitude=17.0385,
    )

    before_run = daily_weather.datetime.fromisoformat("2026-06-25T05:00:00+00:00")
    after_run = daily_weather.datetime.fromisoformat("2026-06-25T06:00:00+00:00")

    assert daily_weather.next_daily_weather_run(before_run, config).isoformat() == "2026-06-25T07:30:00+02:00"
    assert daily_weather.next_daily_weather_run(after_run, config).isoformat() == "2026-06-26T07:30:00+02:00"


def test_daily_weather_report_parses_open_meteo_payload():
    daily_weather = load_daily_weather()
    config = daily_weather.DailyWeatherConfig(
        enabled=True,
        local_time=daily_weather.time(hour=7, minute=30),
        timezone_name="Europe/Warsaw",
        city="Wrocław",
        latitude=51.1079,
        longitude=17.0385,
    )
    payload = {
        "current": {
            "temperature_2m": 21.4,
            "apparent_temperature": 22.1,
            "relative_humidity_2m": 61,
            "precipitation": 0,
            "weather_code": 2,
            "wind_speed_10m": 11.2,
        },
        "daily": {
            "time": ["2026-06-25"],
            "weather_code": [2],
            "temperature_2m_max": [26.1],
            "temperature_2m_min": [15.8],
            "precipitation_probability_max": [20],
            "precipitation_sum": [0.4],
            "sunrise": ["2026-06-25T04:39"],
            "sunset": ["2026-06-25T21:12"],
        },
        "hourly": {
            "time": [
                "2026-06-25T05:00",
                "2026-06-25T06:00",
                "2026-06-25T07:00",
                "2026-06-26T00:00",
            ],
            "temperature_2m": [19.8, 21.4, 22.1, 17.0],
            "precipitation_probability": [5, 35, 80, 20],
            "precipitation": [0, 0.2, 1.4, 0.1],
            "rain": [0, 0.2, 1.0, 0],
            "showers": [0, 0, 0.4, 0],
            "snowfall": [0, 0, 0, 0.1],
        },
    }

    report = daily_weather.build_weather_report(
        config=config,
        payload=payload,
        generated_at=daily_weather.datetime.fromisoformat("2026-06-25T05:31:00+00:00"),
    )

    assert report["schemaVersion"] == 2
    assert report["id"] == "wroclaw-2026-06-25"
    assert report["city"] == "Wrocław"
    assert report["weekday"] == "czwartek"
    assert report["conditions"]["label"] == "Częściowe zachmurzenie"
    assert "start dnia" not in report["headline"]
    assert "poranek" in report["headline"]
    assert report["temperature"]["current"] == 21.4
    assert report["precipitation"]["probability"] == 20
    assert "Łucja" in report["nameDays"]
    assert "Imieniny" in report["summary"]
    assert report["hourlyTemperature"] == [
        {"time": "2026-06-25T05:00", "temperature": 19.8, "unit": "°C"},
        {"time": "2026-06-25T06:00", "temperature": 21.4, "unit": "°C"},
        {"time": "2026-06-25T07:00", "temperature": 22.1, "unit": "°C"},
    ]
    assert report["temperatureTimeline"] == [
        {"time": "2026-06-25T07:00", "temperature": 22.1, "unit": "°C"},
    ]
    assert report["hourlyPrecipitation"] == [
        {
            "time": "2026-06-25T05:00",
            "probability": 5,
            "amount": 0,
            "rain": 0,
            "showers": 0,
            "snowfall": 0,
            "kind": "possible",
            "unit": "mm",
        },
        {
            "time": "2026-06-25T06:00",
            "probability": 35,
            "amount": 0.2,
            "rain": 0.2,
            "showers": 0,
            "snowfall": 0,
            "kind": "rain",
            "unit": "mm",
        },
        {
            "time": "2026-06-25T07:00",
            "probability": 80,
            "amount": 1.4,
            "rain": 1.0,
            "showers": 0.4,
            "snowfall": 0,
            "kind": "rain",
            "unit": "mm",
        },
    ]
    assert report["precipitationTimeline"] == [
        {
            "time": "2026-06-25T07:00",
            "probability": 80,
            "amount": 1.4,
            "rain": 1.0,
            "showers": 0.4,
            "snowfall": 0,
            "kind": "rain",
            "unit": "mm",
        },
    ]


def test_daily_weather_open_meteo_request_includes_hourly_precipitation(monkeypatch):
    daily_weather = load_daily_weather()
    config = daily_weather.DailyWeatherConfig(
        enabled=True,
        local_time=daily_weather.time(hour=7, minute=30),
        timezone_name="Europe/Warsaw",
        city="Wrocław",
        latitude=51.1079,
        longitude=17.0385,
    )
    captured: dict[str, object] = {}

    class FakeResponse:
        def raise_for_status(self):
            pass

        def json(self):
            return {
                "current": {
                    "temperature_2m": 21.4,
                    "apparent_temperature": 22.1,
                    "relative_humidity_2m": 61,
                    "weather_code": 2,
                    "wind_speed_10m": 11.2,
                },
                "daily": {
                    "time": ["2026-06-25"],
                    "weather_code": [2],
                    "temperature_2m_max": [26.1],
                    "temperature_2m_min": [15.8],
                    "precipitation_probability_max": [20],
                    "precipitation_sum": [0.4],
                },
                "hourly": {
                    "time": ["2026-06-25T07:00"],
                    "temperature_2m": [22.1],
                    "precipitation_probability": [80],
                    "precipitation": [1.4],
                    "rain": [1.0],
                    "showers": [0.4],
                    "snowfall": [0],
                },
            }

    class FakeAsyncClient:
        def __init__(self, *args, **kwargs):
            pass

        async def __aenter__(self):
            return self

        async def __aexit__(self, exc_type, exc, traceback):
            return False

        async def get(self, url, params):
            captured["url"] = url
            captured["params"] = params
            return FakeResponse()

    monkeypatch.setitem(sys.modules, "httpx", SimpleNamespace(AsyncClient=FakeAsyncClient))

    report = asyncio.run(
        daily_weather.fetch_daily_weather_report(
            config=config,
            generated_at=daily_weather.datetime.fromisoformat("2026-06-25T05:31:00+00:00"),
        )
    )

    assert captured["url"] == "https://api.open-meteo.com/v1/forecast"
    assert captured["params"]["hourly"] == [
        "temperature_2m",
        "precipitation_probability",
        "precipitation",
        "rain",
        "showers",
        "snowfall",
    ]
    assert report["precipitationTimeline"][0]["kind"] == "rain"


def test_daily_weather_recommendation_names_continuous_rain_hours():
    daily_weather = load_daily_weather()
    config = daily_weather.DailyWeatherConfig(
        enabled=True,
        local_time=daily_weather.time(hour=7, minute=30),
        timezone_name="Europe/Warsaw",
        city="Wrocław",
        latitude=51.1079,
        longitude=17.0385,
    )
    payload = {
        "current": {
            "temperature_2m": 18.0,
            "apparent_temperature": 17.5,
            "relative_humidity_2m": 78,
            "weather_code": 61,
            "wind_speed_10m": 12.0,
        },
        "daily": {
            "time": ["2026-06-25"],
            "weather_code": [61],
            "temperature_2m_max": [21.0],
            "temperature_2m_min": [14.0],
            "precipitation_probability_max": [90],
            "precipitation_sum": [3.6],
        },
        "hourly": {
            "time": [
                "2026-06-25T07:00",
                "2026-06-25T08:00",
                "2026-06-25T09:00",
            ],
            "temperature_2m": [18.0, 18.4, 19.0],
            "precipitation_probability": [75, 90, 70],
            "precipitation": [0.5, 1.2, 0.8],
            "rain": [0.5, 1.2, 0.8],
            "showers": [0, 0, 0],
            "snowfall": [0, 0, 0],
        },
    }

    report = daily_weather.build_weather_report(
        config=config,
        payload=payload,
        generated_at=daily_weather.datetime.fromisoformat("2026-06-25T05:15:00+00:00"),
    )

    assert "opadów deszczu spodziewaj się około 07:00-09:00" in report["recommendation"]


def test_daily_weather_recommendation_names_separate_rain_windows():
    daily_weather = load_daily_weather()
    config = daily_weather.DailyWeatherConfig(
        enabled=True,
        local_time=daily_weather.time(hour=7, minute=30),
        timezone_name="Europe/Warsaw",
        city="Wrocław",
        latitude=51.1079,
        longitude=17.0385,
    )
    payload = {
        "current": {
            "temperature_2m": 19.0,
            "apparent_temperature": 19.0,
            "relative_humidity_2m": 80,
            "weather_code": 80,
            "wind_speed_10m": 10.0,
        },
        "daily": {
            "time": ["2026-06-25"],
            "weather_code": [80],
            "temperature_2m_max": [23.0],
            "temperature_2m_min": [13.0],
            "precipitation_probability_max": [80],
            "precipitation_sum": [2.2],
        },
        "hourly": {
            "time": [
                "2026-06-25T07:00",
                "2026-06-25T08:00",
                "2026-06-25T16:00",
            ],
            "temperature_2m": [19.0, 19.5, 21.0],
            "precipitation_probability": [70, 80, 65],
            "precipitation": [0.3, 0.7, 1.2],
            "rain": [0.3, 0.7, 1.2],
            "showers": [0, 0, 0],
            "snowfall": [0, 0, 0],
        },
    }

    report = daily_weather.build_weather_report(
        config=config,
        payload=payload,
        generated_at=daily_weather.datetime.fromisoformat("2026-06-25T05:00:00+00:00"),
    )

    assert "około 07:00-08:00 i 16:00" in report["recommendation"]


def test_daily_weather_recommendation_names_possible_precipitation_hours():
    daily_weather = load_daily_weather()
    config = daily_weather.DailyWeatherConfig(
        enabled=True,
        local_time=daily_weather.time(hour=7, minute=30),
        timezone_name="Europe/Warsaw",
        city="Wrocław",
        latitude=51.1079,
        longitude=17.0385,
    )
    payload = {
        "current": {
            "temperature_2m": 20.0,
            "apparent_temperature": 20.0,
            "relative_humidity_2m": 65,
            "weather_code": 3,
            "wind_speed_10m": 8.0,
        },
        "daily": {
            "time": ["2026-06-25"],
            "weather_code": [3],
            "temperature_2m_max": [24.0],
            "temperature_2m_min": [15.0],
            "precipitation_probability_max": [45],
            "precipitation_sum": [0],
        },
        "hourly": {
            "time": ["2026-06-25T15:00"],
            "temperature_2m": [23.0],
            "precipitation_probability": [45],
            "precipitation": [0],
            "rain": [0],
            "showers": [0],
            "snowfall": [0],
        },
    }

    report = daily_weather.build_weather_report(
        config=config,
        payload=payload,
        generated_at=daily_weather.datetime.fromisoformat("2026-06-25T05:00:00+00:00"),
    )

    assert "ryzyko opadów widać około 15:00" in report["recommendation"]
    assert "opadów deszczu" not in report["recommendation"]


def test_daily_weather_recommendation_omits_false_hours_without_significant_precipitation():
    daily_weather = load_daily_weather()
    config = daily_weather.DailyWeatherConfig(
        enabled=True,
        local_time=daily_weather.time(hour=7, minute=30),
        timezone_name="Europe/Warsaw",
        city="Wrocław",
        latitude=51.1079,
        longitude=17.0385,
    )
    payload = {
        "current": {
            "temperature_2m": 22.0,
            "apparent_temperature": 22.0,
            "relative_humidity_2m": 55,
            "weather_code": 1,
            "wind_speed_10m": 7.0,
        },
        "daily": {
            "time": ["2026-06-25"],
            "weather_code": [1],
            "temperature_2m_max": [26.0],
            "temperature_2m_min": [16.0],
            "precipitation_probability_max": [15],
            "precipitation_sum": [0],
        },
        "hourly": {
            "time": ["2026-06-25T12:00", "2026-06-25T18:00"],
            "temperature_2m": [24.0, 23.0],
            "precipitation_probability": [10, 15],
            "precipitation": [0, 0],
            "rain": [0, 0],
            "showers": [0, 0],
            "snowfall": [0, 0],
        },
    }

    report = daily_weather.build_weather_report(
        config=config,
        payload=payload,
        generated_at=daily_weather.datetime.fromisoformat("2026-06-25T05:00:00+00:00"),
    )

    assert "do końca dnia nie widać istotnych opadów" in report["recommendation"]
    assert "12:00" not in report["recommendation"]
    assert "18:00" not in report["recommendation"]


def test_daily_weather_headline_is_contextual_for_evening():
    daily_weather = load_daily_weather()
    config = daily_weather.DailyWeatherConfig(
        enabled=True,
        local_time=daily_weather.time(hour=7, minute=30),
        timezone_name="Europe/Warsaw",
        city="Wrocław",
        latitude=51.1079,
        longitude=17.0385,
    )

    headline = daily_weather.weather_headline(
        city="Wrocław",
        condition="Częściowe zachmurzenie",
        current_temperature=27.5,
        max_temperature=32.4,
        generated_at=daily_weather.datetime.fromisoformat("2026-06-25T20:02:00+00:00"),
        config=config,
    )
    recommendation = daily_weather.weather_recommendation(
        precipitation_probability=0,
        wind_speed=3.6,
        apparent_temperature=29.5,
        generated_at=daily_weather.datetime.fromisoformat("2026-06-25T20:02:00+00:00"),
        config=config,
    )

    assert "start dnia" not in headline
    assert "wieczór" in headline
    assert recommendation.startswith("Na wieczór:")


def test_daily_weather_config_can_be_overridden_with_location():
    daily_weather = load_daily_weather()
    config = daily_weather.DailyWeatherConfig(
        enabled=True,
        local_time=daily_weather.time(hour=7, minute=30),
        timezone_name="Europe/Warsaw",
        city="Wrocław",
        latitude=51.1079,
        longitude=17.0385,
    )

    location_config = config.with_location(latitude=52.2297, longitude=21.0122, city="Warszawa")

    assert location_config.city == "Warszawa"
    assert location_config.latitude == 52.2297
    assert location_config.longitude == 21.0122
    assert location_config.local_time == config.local_time


def test_daily_humor_parses_reddit_listing_and_filters_unsafe_items():
    daily_humor = load_daily_humor()
    payload = {
        "data": {
            "children": [
                {
                    "data": {
                        "id": "safe1",
                        "title": "Kiedy deploy przechodzi za pierwszym razem",
                        "permalink": "/r/ProgrammerHumor/comments/safe1/test/",
                        "url": "https://i.redd.it/example.png",
                        "score": 1200,
                        "num_comments": 42,
                        "over_18": False,
                        "stickied": False,
                    }
                },
                {
                    "data": {
                        "id": "unsafe",
                        "title": "NSFW item",
                        "permalink": "/r/memes/comments/unsafe/test/",
                        "score": 9999,
                        "over_18": True,
                    }
                },
            ]
        }
    }

    items = daily_humor.parse_reddit_listing(payload, source_name="r/ProgrammerHumor")

    assert len(items) == 1
    assert items[0]["id"] == "safe1"
    assert items[0]["imageURL"] == "https://i.redd.it/example.png"
    assert "dev" in items[0]["tags"]


def test_daily_humor_builds_reddit_radar_summary_from_categories():
    daily_humor = load_daily_humor()
    config = daily_humor.DailyHumorConfig(
        enabled=True,
        interval_hours=3,
        timezone_name="Europe/Warsaw",
        max_items=3,
        sources=[],
    )

    digest = daily_humor.build_humor_digest(
        items=[
            {
                "id": "ai-dev",
                "title": "Kiedy AI robi code review po piątku",
                "caption": "AI robi swoje, ludzie robią screeny, internet robi resztę.",
                "sourceName": "r/ProgrammerHumor",
                "sourceURL": "https://www.reddit.com/r/ProgrammerHumor/comments/ai_dev/test/",
                "imageURL": None,
                "score": 1200,
                "comments": 91,
                "tags": ["AI", "dev"],
                "categoryLabel": "AI, dev",
                "postText": "Autor żartuje, że AI znalazło błąd, którego nikt nie napisał.",
                "whyFunny": "Zabawne, bo AI zachowuje się jak bardzo pewny siebie reviewer.",
                "commentHighlights": [
                    {
                        "id": "comment-1",
                        "summary": "Wszyscy udają, że rozumieją komentarz bota.",
                        "explanation": "Komentarz punktuje teatralną stronę code review.",
                        "score": 44,
                    }
                ],
            },
            {
                "id": "pl",
                "title": "Polski internet odkrył nowy rytuał",
                "caption": "Sygnał społecznościowy z Reddita.",
                "sourceName": "r/Polska_wpz",
                "sourceURL": "https://www.reddit.com/r/Polska_wpz/comments/pl/test/",
                "imageURL": None,
                "score": 300,
                "comments": 21,
                "tags": ["PL", "trend"],
                "categoryLabel": "PL",
                "commentHighlights": [],
            },
        ],
        config=config,
        generated_at=daily_humor.datetime.fromisoformat("2026-06-27T08:15:00+00:00"),
    )

    assert digest["title"] == "<RR> Reddit Radar"
    assert digest["summary"] == (
        "Kategorie: AI, dev, PL. Najmocniej wybija się: "
        "<u>Kiedy AI robi code review po piątku</u>."
    )
    assert digest["items"][0]["whyFunny"].startswith("Zabawne")
    assert digest["items"][0]["commentHighlights"][0]["score"] == 44


def test_humor_digest_payload_declares_reddit_radar_detail_fields():
    server_path = (
        Path(__file__).resolve().parents[1]
        / "backend"
        / "pavbot-notifier"
        / "pavbot_notifier"
        / "server.py"
    )
    tree = ast.parse(server_path.read_text(encoding="utf-8"))
    classes = {node.name: node for node in tree.body if isinstance(node, ast.ClassDef)}
    item_class = classes["HumorDigestItemPayload"]
    comment_class = classes["HumorDigestCommentHighlightPayload"]

    item_fields = {
        statement.target.id
        for statement in item_class.body
        if isinstance(statement, ast.AnnAssign) and isinstance(statement.target, ast.Name)
    }
    comment_fields = {
        statement.target.id
        for statement in comment_class.body
        if isinstance(statement, ast.AnnAssign) and isinstance(statement.target, ast.Name)
    }

    assert {"categoryLabel", "postText", "whyFunny", "commentHighlights"} <= item_fields
    assert {"id", "summary", "explanation", "score"} <= comment_fields


def test_daily_humor_defaults_to_reddit_only_sources(monkeypatch):
    daily_humor = load_daily_humor()
    monkeypatch.delenv("PAVBOT_REDDIT_SUBREDDITS", raising=False)

    config = daily_humor.DailyHumorConfig.from_env()

    assert config.reddit_subreddits == ("Polska_wpz", "memes", "ProgrammerHumor")
    assert all("reddit.com" in url for _, url in config.sources)
    assert all("lemmy" not in url for _, url in config.sources)


def test_daily_humor_fetch_requires_reddit_oauth_credentials():
    daily_humor = load_daily_humor()
    config = daily_humor.DailyHumorConfig(
        enabled=True,
        interval_hours=3,
        timezone_name="Europe/Warsaw",
        max_items=3,
    )

    with pytest.raises(daily_humor.RedditConfigurationError, match="Reddit OAuth credentials"):
        asyncio.run(daily_humor.fetch_humor_items(config=config))


def test_daily_humor_fetches_reddit_oauth_access_token():
    daily_humor = load_daily_humor()

    class FakeResponse:
        status_code = 200

        def json(self):
            return {"access_token": "token-123"}

    class FakeClient:
        def __init__(self):
            self.calls = []

        async def post(self, url, data, auth, headers):
            self.calls.append({"url": url, "data": data, "auth": auth, "headers": headers})
            return FakeResponse()

    client = FakeClient()
    config = daily_humor.DailyHumorConfig(
        enabled=True,
        interval_hours=3,
        timezone_name="Europe/Warsaw",
        max_items=3,
        reddit_client_id="client-id",
        reddit_client_secret="client-secret",
        reddit_user_agent="PavbotNotifier/1.0 by test",
    )

    token = asyncio.run(daily_humor.fetch_reddit_access_token(client=client, config=config))

    assert token == "token-123"
    assert client.calls[0]["url"] == "https://www.reddit.com/api/v1/access_token"
    assert client.calls[0]["data"] == {"grant_type": "client_credentials"}
    assert client.calls[0]["auth"] == ("client-id", "client-secret")
    assert client.calls[0]["headers"]["User-Agent"] == "PavbotNotifier/1.0 by test"


def test_daily_humor_refresh_window_is_three_hours():
    daily_humor = load_daily_humor()
    config = daily_humor.DailyHumorConfig(
        enabled=True,
        interval_hours=3,
        timezone_name="Europe/Warsaw",
        max_items=3,
        sources=[],
    )
    first = daily_humor.datetime.fromisoformat("2026-06-25T08:15:00+00:00")
    same_window = daily_humor.datetime.fromisoformat("2026-06-25T08:59:00+00:00")
    next_window = daily_humor.datetime.fromisoformat("2026-06-25T10:01:00+00:00")
    digest = daily_humor.build_humor_digest(
        items=daily_humor.fallback_humor_items(3),
        config=config,
        generated_at=first,
    )

    assert not daily_humor.humor_digest_is_current_window(digest, now=same_window, config=config)

    reddit_digest = daily_humor.build_humor_digest(
        items=[
            {
                "id": "reddit-item",
                "title": "Kiedy Reddit mówi: hot means hot",
                "caption": "Krótki memowy sygnał, dobry do szybkiego przewinięcia.",
                "sourceName": "r/memes",
                "sourceURL": "https://www.reddit.com/r/memes/comments/test/",
                "imageURL": None,
                "score": 100,
                "comments": 10,
                "tags": ["memy"],
            }
        ],
        config=config,
        generated_at=first,
    )
    assert daily_humor.humor_digest_is_current_window(reddit_digest, now=same_window, config=config)
    assert not daily_humor.humor_digest_is_current_window(reddit_digest, now=next_window, config=config)
    assert daily_humor.next_humor_refresh(first, config).isoformat() == "2026-06-25T12:00:00+02:00"


def test_daily_humor_legacy_fallback_items_do_not_mask_reddit_outage():
    daily_humor = load_daily_humor()
    config = daily_humor.DailyHumorConfig(
        enabled=True,
        interval_hours=3,
        timezone_name="Europe/Warsaw",
        max_items=3,
    )
    now = daily_humor.datetime.fromisoformat("2026-06-25T08:59:00+00:00")
    digest = daily_humor.build_humor_digest(
        items=daily_humor.fallback_humor_items(3),
        config=config,
        generated_at=daily_humor.datetime.fromisoformat("2026-06-25T08:15:00+00:00"),
    )
    digest["source"] = "Public Reddit trend feeds"

    assert daily_humor.humor_digest_uses_fallback(digest) is True
    assert not daily_humor.humor_digest_is_current_window(digest, now=now, config=config)


def test_daily_humor_status_reports_digest(tmp_path):
    daily_humor = load_daily_humor()
    config = daily_humor.DailyHumorConfig(
        enabled=True,
        interval_hours=3,
        timezone_name="Europe/Warsaw",
        max_items=2,
        sources=[],
    )
    digest = daily_humor.build_humor_digest(
        items=daily_humor.fallback_humor_items(2),
        config=config,
        generated_at=daily_humor.datetime.fromisoformat("2026-06-25T08:15:00+00:00"),
    )
    (tmp_path / "last-daily-humor.json").write_text(
        json.dumps({"lastDigest": digest, "lastRefreshAt": digest["generatedAt"]}),
        encoding="utf-8",
    )

    status = daily_humor.daily_humor_status(storage_dir=tmp_path, config=config)

    assert status["enabled"] is True
    assert status["intervalHours"] == 3
    assert status["lastDigest"]["itemCount"] == 2
    assert status["redditOAuthConfigured"] is False
    assert status["redditSubreddits"] == ["Polska_wpz", "memes", "ProgrammerHumor"]


def test_daily_humor_external_mode_serves_last_codex_digest_even_when_stale(tmp_path):
    daily_humor = load_daily_humor()
    config = daily_humor.DailyHumorConfig(
        enabled=True,
        interval_hours=2,
        timezone_name="Europe/Warsaw",
        max_items=2,
        source_mode="external",
    )
    digest = {
        "id": "humor-2026-06-26-22",
        "title": "Codex radar Reddita",
        "summary": "Codex zebrał lekkie sygnały z zalogowanego Reddita.",
        "generatedAt": "2026-06-26T20:06:00+00:00",
        "displayTime": "22:06",
        "nextRefreshAt": "2026-06-27T00:06:00+02:00",
        "refreshIntervalHours": 2,
        "source": "Codex Safari Reddit radar",
        "items": [
            {
                "id": "reddit-test",
                "title": "Kiedy Reddit znajduje temat dnia",
                "caption": "Krótki sygnał społecznościowy, nie źródło faktów.",
                "sourceName": "r/Polska_wpz",
                "sourceURL": "https://www.reddit.com/r/Polska_wpz/comments/test/example/",
                "imageURL": None,
                "score": 321,
                "comments": 45,
                "tags": ["PL", "trend"],
            }
        ],
    }

    daily_humor.save_external_humor_digest(
        digest=digest,
        storage_dir=tmp_path,
        received_at=daily_humor.datetime.fromisoformat("2026-06-26T20:06:30+00:00"),
    )

    result = asyncio.run(
        daily_humor.latest_humor_digest(
            config=config,
            storage_dir=tmp_path,
            now=daily_humor.datetime.fromisoformat("2026-06-27T08:30:00+00:00"),
        )
    )
    state = json.loads((tmp_path / "last-daily-humor.json").read_text(encoding="utf-8"))

    assert result["id"] == "humor-2026-06-26-22"
    assert result["source"] == "Codex Safari Reddit radar"
    assert state["producer"] == "codex-safari"
    assert state["lastError"] is None


def test_humor_digest_ingest_requires_bearer_token(tmp_path):
    daily_humor = load_daily_humor()
    payload = {
        "id": "humor-2026-06-27-08",
        "title": "Codex radar Reddita",
        "summary": "Codex wybrał świeże sygnały humoru.",
        "generatedAt": "2026-06-27T06:06:00+00:00",
        "displayTime": "08:06",
        "nextRefreshAt": "2026-06-27T10:06:00+02:00",
        "refreshIntervalHours": 2,
        "source": "Codex Safari Reddit radar",
        "items": [
            {
                "id": "reddit-test",
                "title": "Kiedy automatyzacja działa",
                "caption": "Lekki sygnał z Reddita.",
                "sourceName": "r/memes",
                "sourceURL": "https://www.reddit.com/r/memes/comments/test/example/",
                "imageURL": None,
                "score": 500,
                "comments": 12,
                "tags": ["memy"],
            }
        ],
    }

    assert daily_humor.humor_ingest_token_is_valid(None, expected_token="secret-token") is False
    assert daily_humor.humor_ingest_token_is_valid("Bearer wrong-token", expected_token="secret-token") is False
    assert daily_humor.humor_ingest_token_is_valid("Bearer secret-token", expected_token="secret-token") is True

    result = daily_humor.save_external_humor_digest(
        digest=payload,
        storage_dir=tmp_path,
        received_at=daily_humor.datetime.fromisoformat("2026-06-27T06:06:30+00:00"),
    )
    latest = asyncio.run(
        daily_humor.latest_humor_digest(
            config=daily_humor.DailyHumorConfig(
                enabled=True,
                interval_hours=2,
                timezone_name="Europe/Warsaw",
                max_items=6,
                source_mode="external",
            ),
            storage_dir=tmp_path,
            now=daily_humor.datetime.fromisoformat("2026-06-27T06:07:00+00:00"),
        )
    )

    assert result["status"] == "stored"
    assert latest["source"] == "Codex Safari Reddit radar"
    assert latest["items"][0]["sourceURL"].startswith("https://www.reddit.com/")


def test_daily_weather_manual_refresh_saves_report_without_sending_pushes(tmp_path, monkeypatch):
    daily_weather = load_daily_weather()
    config = daily_weather.DailyWeatherConfig(
        enabled=True,
        local_time=daily_weather.time(hour=7, minute=30),
        timezone_name="Europe/Warsaw",
        city="Wrocław",
        latitude=51.1079,
        longitude=17.0385,
    )
    calls = {"fetch": 0}

    async def fake_fetch_daily_weather_report(*, config, generated_at):
        calls["fetch"] += 1
        return {
            "id": "wroclaw-2026-06-25",
            "city": config.city,
            "date": "2026-06-25",
            "generatedAt": generated_at.isoformat(),
            "hourlyTemperature": [
                {"time": "2026-06-25T12:00", "temperature": 24.2, "unit": "°C"},
            ],
        }

    monkeypatch.setattr(daily_weather, "fetch_daily_weather_report", fake_fetch_daily_weather_report)

    result = asyncio.run(
        daily_weather.refresh_daily_weather_report(
            config=config,
            storage_dir=tmp_path,
            generated_at=daily_weather.datetime.fromisoformat("2026-06-25T10:15:00+00:00"),
        )
    )
    state = json.loads((tmp_path / "last-daily-weather.json").read_text(encoding="utf-8"))

    assert calls["fetch"] == 1
    assert result["status"] == "refreshed"
    assert result["report"]["hourlyTemperature"][0]["temperature"] == 24.2
    assert state["lastManualRefreshAt"] == "2026-06-25T10:15:00+00:00"
    assert state["lastReport"]["id"] == "wroclaw-2026-06-25"
    assert "lastDelivery" not in result


def test_daily_weather_manual_refresh_is_blocked_until_next_hour(tmp_path, monkeypatch):
    daily_weather = load_daily_weather()
    config = daily_weather.DailyWeatherConfig(
        enabled=True,
        local_time=daily_weather.time(hour=7, minute=30),
        timezone_name="Europe/Warsaw",
        city="Wrocław",
        latitude=51.1079,
        longitude=17.0385,
    )
    (tmp_path / "last-daily-weather.json").write_text(
        json.dumps(
            {
                "lastManualRefreshAt": "2026-06-25T10:15:00+00:00",
                "lastReport": {"id": "wroclaw-2026-06-25"},
            }
        ),
        encoding="utf-8",
    )
    calls = {"fetch": 0}

    async def fake_fetch_daily_weather_report(*, config, generated_at):
        calls["fetch"] += 1
        return {"id": "should-not-fetch"}

    monkeypatch.setattr(daily_weather, "fetch_daily_weather_report", fake_fetch_daily_weather_report)

    with pytest.raises(daily_weather.DailyWeatherRefreshLocked) as exc:
        asyncio.run(
            daily_weather.refresh_daily_weather_report(
                config=config,
                storage_dir=tmp_path,
                generated_at=daily_weather.datetime.fromisoformat("2026-06-25T10:30:00+00:00"),
            )
        )

    state = json.loads((tmp_path / "last-daily-weather.json").read_text(encoding="utf-8"))
    assert calls["fetch"] == 0
    assert exc.value.retry_at.isoformat() == "2026-06-25T13:00:00+02:00"
    assert exc.value.last_report == {"id": "wroclaw-2026-06-25"}
    assert state["lastManualRefreshBlockedAt"] == "2026-06-25T10:30:00+00:00"
    assert state["manualRefreshRetryAt"] == "2026-06-25T13:00:00+02:00"


def test_daily_weather_status_reports_last_manual_refresh(tmp_path):
    daily_weather = load_daily_weather()
    config = daily_weather.DailyWeatherConfig(
        enabled=True,
        local_time=daily_weather.time(hour=7, minute=30),
        timezone_name="Europe/Warsaw",
        city="Wrocław",
        latitude=51.1079,
        longitude=17.0385,
    )
    (tmp_path / "last-daily-weather.json").write_text(
        json.dumps({"lastManualRefreshAt": "2026-06-25T10:15:00+00:00"}),
        encoding="utf-8",
    )

    status = daily_weather.daily_weather_status(storage_dir=tmp_path, config=config)

    assert status["lastManualRefreshAt"] == "2026-06-25T10:15:00+00:00"


def test_daily_weather_status_reports_manual_refresh_retry_at(tmp_path):
    daily_weather = load_daily_weather()
    config = daily_weather.DailyWeatherConfig(
        enabled=True,
        local_time=daily_weather.time(hour=7, minute=30),
        timezone_name="Europe/Warsaw",
        city="Wrocław",
        latitude=51.1079,
        longitude=17.0385,
    )
    (tmp_path / "last-daily-weather.json").write_text(
        json.dumps(
            {
                "lastManualRefreshAt": "2026-06-25T10:15:00+00:00",
                "manualRefreshRetryAt": "2026-06-25T13:00:00+02:00",
            }
        ),
        encoding="utf-8",
    )

    status = daily_weather.daily_weather_status(storage_dir=tmp_path, config=config)

    assert status["manualRefreshRetryAt"] == "2026-06-25T13:00:00+02:00"


def test_hourly_weather_refresh_updates_cache_without_sending_pushes(tmp_path, monkeypatch):
    daily_weather = load_daily_weather()
    config = daily_weather.DailyWeatherConfig(
        enabled=True,
        local_time=daily_weather.time(hour=7, minute=30),
        timezone_name="Europe/Warsaw",
        city="Wrocław",
        latitude=51.1079,
        longitude=17.0385,
    )
    calls = {"fetch": 0}

    async def fake_fetch_daily_weather_report(*, config, generated_at):
        calls["fetch"] += 1
        return {
            "id": "wroclaw-2026-06-25",
            "city": config.city,
            "date": "2026-06-25",
            "generatedAt": generated_at.isoformat(),
            "hourlyTemperature": [
                {"time": "2026-06-25T13:00", "temperature": 25.0, "unit": "°C"},
            ],
        }

    monkeypatch.setattr(daily_weather, "fetch_daily_weather_report", fake_fetch_daily_weather_report)

    result = asyncio.run(
        daily_weather.run_hourly_weather_refresh_once(
            config=config,
            storage_dir=tmp_path,
            generated_at=daily_weather.datetime.fromisoformat("2026-06-25T11:05:00+00:00"),
        )
    )
    state = json.loads((tmp_path / "last-daily-weather.json").read_text(encoding="utf-8"))

    assert calls["fetch"] == 1
    assert result["status"] == "refreshed"
    assert result["report"]["hourlyTemperature"][0]["temperature"] == 25.0
    assert state["lastHourlyRefreshAt"] == "2026-06-25T11:05:00+00:00"
    assert state["nextHourlyRefreshAt"] == "2026-06-25T14:00:00+02:00"
    assert state["lastHourlyError"] is None
    assert "lastDelivery" not in state


def test_hourly_weather_refresh_skips_when_current_hour_is_cached(tmp_path, monkeypatch):
    daily_weather = load_daily_weather()
    config = daily_weather.DailyWeatherConfig(
        enabled=True,
        local_time=daily_weather.time(hour=7, minute=30),
        timezone_name="Europe/Warsaw",
        city="Wrocław",
        latitude=51.1079,
        longitude=17.0385,
    )
    (tmp_path / "last-daily-weather.json").write_text(
        json.dumps(
            {
                "lastHourlyRefreshAt": "2026-06-25T11:05:00+00:00",
                "lastReport": {
                    "schemaVersion": 2,
                    "id": "wroclaw-2026-06-25",
                    "city": "Wrocław",
                    "date": "2026-06-25",
                    "generatedAt": "2026-06-25T11:05:00+00:00",
                    "temperatureTimeline": [
                        {"time": "2026-06-25T13:00", "temperature": 25.0, "unit": "°C"}
                    ],
                    "hourlyPrecipitation": [
                        {
                            "time": "2026-06-25T13:00",
                            "probability": 10,
                            "amount": 0,
                            "rain": 0,
                            "showers": 0,
                            "snowfall": 0,
                            "kind": "possible",
                            "unit": "mm",
                        }
                    ],
                    "precipitationTimeline": [
                        {
                            "time": "2026-06-25T13:00",
                            "probability": 10,
                            "amount": 0,
                            "rain": 0,
                            "showers": 0,
                            "snowfall": 0,
                            "kind": "possible",
                            "unit": "mm",
                        }
                    ],
                },
            }
        ),
        encoding="utf-8",
    )
    calls = {"fetch": 0}

    async def fake_fetch_daily_weather_report(*, config, generated_at):
        calls["fetch"] += 1
        return {"id": "should-not-fetch"}

    monkeypatch.setattr(daily_weather, "fetch_daily_weather_report", fake_fetch_daily_weather_report)

    result = asyncio.run(
        daily_weather.run_hourly_weather_refresh_once(
            config=config,
            storage_dir=tmp_path,
            generated_at=daily_weather.datetime.fromisoformat("2026-06-25T11:40:00+00:00"),
        )
    )

    assert calls["fetch"] == 0
    assert result["status"] == "skipped"
    assert result["skippedReason"] == "Weather report already refreshed for this local hour"


def test_hourly_weather_refresh_rebuilds_current_cache_without_precipitation_schema(tmp_path, monkeypatch):
    daily_weather = load_daily_weather()
    config = daily_weather.DailyWeatherConfig(
        enabled=True,
        local_time=daily_weather.time(hour=7, minute=30),
        timezone_name="Europe/Warsaw",
        city="Wrocław",
        latitude=51.1079,
        longitude=17.0385,
    )
    (tmp_path / "last-daily-weather.json").write_text(
        json.dumps(
            {
                "lastHourlyRefreshAt": "2026-06-25T11:05:00+00:00",
                "lastReport": {
                    "id": "wroclaw-2026-06-25",
                    "city": "Wrocław",
                    "date": "2026-06-25",
                    "generatedAt": "2026-06-25T11:05:00+00:00",
                    "temperatureTimeline": [
                        {"time": "2026-06-25T13:00", "temperature": 25.0, "unit": "°C"}
                    ],
                },
            }
        ),
        encoding="utf-8",
    )
    calls = {"fetch": 0}

    async def fake_fetch_daily_weather_report(*, config, generated_at):
        calls["fetch"] += 1
        return {
            "schemaVersion": 2,
            "id": "wroclaw-2026-06-25",
            "city": config.city,
            "date": "2026-06-25",
            "generatedAt": generated_at.isoformat(),
            "temperatureTimeline": [
                {"time": "2026-06-25T13:00", "temperature": 25.0, "unit": "°C"}
            ],
            "hourlyPrecipitation": [
                {
                    "time": "2026-06-25T13:00",
                    "probability": 70,
                    "amount": 0.4,
                    "rain": 0.4,
                    "showers": 0,
                    "snowfall": 0,
                    "kind": "rain",
                    "unit": "mm",
                }
            ],
            "precipitationTimeline": [
                {
                    "time": "2026-06-25T13:00",
                    "probability": 70,
                    "amount": 0.4,
                    "rain": 0.4,
                    "showers": 0,
                    "snowfall": 0,
                    "kind": "rain",
                    "unit": "mm",
                }
            ],
        }

    monkeypatch.setattr(daily_weather, "fetch_daily_weather_report", fake_fetch_daily_weather_report)

    result = asyncio.run(
        daily_weather.run_hourly_weather_refresh_once(
            config=config,
            storage_dir=tmp_path,
            generated_at=daily_weather.datetime.fromisoformat("2026-06-25T11:40:00+00:00"),
        )
    )

    assert calls["fetch"] == 1
    assert result["status"] == "refreshed"
    assert result["report"]["precipitationTimeline"][0]["amount"] == 0.4


def test_hourly_weather_refresh_does_not_use_legacy_cache_for_different_location(tmp_path, monkeypatch):
    daily_weather = load_daily_weather()
    config = daily_weather.DailyWeatherConfig(
        enabled=True,
        local_time=daily_weather.time(hour=7, minute=30),
        timezone_name="Europe/Warsaw",
        city="Warszawa",
        latitude=52.2297,
        longitude=21.0122,
    )
    (tmp_path / "last-daily-weather.json").write_text(
        json.dumps(
            {
                "lastHourlyRefreshAt": "2026-06-25T11:05:00+00:00",
                "lastReport": {
                    "id": "wroclaw-2026-06-25",
                    "city": "Wrocław",
                    "date": "2026-06-25",
                    "generatedAt": "2026-06-25T11:05:00+00:00",
                    "temperatureTimeline": [
                        {"time": "2026-06-25T13:00", "temperature": 25.0, "unit": "°C"}
                    ],
                },
            }
        ),
        encoding="utf-8",
    )
    calls = {"fetch": 0}

    async def fake_fetch_daily_weather_report(*, config, generated_at):
        calls["fetch"] += 1
        return {
            "id": "warszawa-2026-06-25",
            "city": config.city,
            "date": "2026-06-25",
            "generatedAt": generated_at.isoformat(),
            "temperatureTimeline": [
                {"time": "2026-06-25T13:00", "temperature": 28.0, "unit": "°C"}
            ],
        }

    monkeypatch.setattr(daily_weather, "fetch_daily_weather_report", fake_fetch_daily_weather_report)

    result = asyncio.run(
        daily_weather.run_hourly_weather_refresh_once(
            config=config,
            storage_dir=tmp_path,
            generated_at=daily_weather.datetime.fromisoformat("2026-06-25T11:40:00+00:00"),
        )
    )
    state = json.loads((tmp_path / "last-daily-weather.json").read_text(encoding="utf-8"))

    assert calls["fetch"] == 1
    assert result["status"] == "refreshed"
    assert result["report"]["city"] == "Warszawa"
    assert any(item["city"] == "Warszawa" for item in state["locationReports"].values())


def test_hourly_weather_refresh_refreshes_current_cache_without_temperature_timeline(tmp_path, monkeypatch):
    daily_weather = load_daily_weather()
    config = daily_weather.DailyWeatherConfig(
        enabled=True,
        local_time=daily_weather.time(hour=7, minute=30),
        timezone_name="Europe/Warsaw",
        city="Wrocław",
        latitude=51.1079,
        longitude=17.0385,
    )
    (tmp_path / "last-daily-weather.json").write_text(
        json.dumps(
            {
                "lastHourlyRefreshAt": "2026-06-25T20:00:00+00:00",
                "lastReport": {
                    "id": "wroclaw-2026-06-25",
                    "city": "Wrocław",
                    "date": "2026-06-25",
                    "generatedAt": "2026-06-25T20:00:00+00:00",
                    "hourlyTemperature": [
                        {"time": "2026-06-25T22:00", "temperature": 27.5, "unit": "°C"},
                    ],
                },
            }
        ),
        encoding="utf-8",
    )
    calls = {"fetch": 0}

    async def fake_fetch_daily_weather_report(*, config, generated_at):
        calls["fetch"] += 1
        return {
            "id": "wroclaw-2026-06-25",
            "city": config.city,
            "date": "2026-06-25",
            "generatedAt": generated_at.isoformat(),
            "hourlyTemperature": [
                {"time": "2026-06-25T22:00", "temperature": 27.5, "unit": "°C"},
            ],
            "temperatureTimeline": [
                {"time": "2026-06-25T22:00", "temperature": 27.5, "unit": "°C"},
            ],
        }

    monkeypatch.setattr(daily_weather, "fetch_daily_weather_report", fake_fetch_daily_weather_report)

    result = asyncio.run(
        daily_weather.run_hourly_weather_refresh_once(
            config=config,
            storage_dir=tmp_path,
            generated_at=daily_weather.datetime.fromisoformat("2026-06-25T20:30:00+00:00"),
        )
    )

    assert calls["fetch"] == 1
    assert result["status"] == "refreshed"
    assert result["report"]["temperatureTimeline"][0]["time"] == "2026-06-25T22:00"


def test_hourly_weather_refresh_refreshes_legacy_start_day_headline(tmp_path, monkeypatch):
    daily_weather = load_daily_weather()
    config = daily_weather.DailyWeatherConfig(
        enabled=True,
        local_time=daily_weather.time(hour=7, minute=30),
        timezone_name="Europe/Warsaw",
        city="Wrocław",
        latitude=51.1079,
        longitude=17.0385,
    )
    (tmp_path / "last-daily-weather.json").write_text(
        json.dumps(
            {
                "lastHourlyRefreshAt": "2026-06-25T20:00:00+00:00",
                "lastReport": {
                    "id": "wroclaw-2026-06-25",
                    "city": "Wrocław",
                    "date": "2026-06-25",
                    "generatedAt": "2026-06-25T20:00:00+00:00",
                    "headline": "Wrocław: częściowe zachmurzenie i 27.5°C na start dnia",
                    "temperatureTimeline": [
                        {"time": "2026-06-25T22:00", "temperature": 27.5, "unit": "°C"},
                    ],
                },
            }
        ),
        encoding="utf-8",
    )
    calls = {"fetch": 0}

    async def fake_fetch_daily_weather_report(*, config, generated_at):
        calls["fetch"] += 1
        return {
            "id": "wroclaw-2026-06-25",
            "city": config.city,
            "date": "2026-06-25",
            "generatedAt": generated_at.isoformat(),
            "headline": "Wrocław: wieczór, częściowe zachmurzenie i 27.5°C",
            "temperatureTimeline": [
                {"time": "2026-06-25T22:00", "temperature": 27.5, "unit": "°C"},
            ],
        }

    monkeypatch.setattr(daily_weather, "fetch_daily_weather_report", fake_fetch_daily_weather_report)

    result = asyncio.run(
        daily_weather.run_hourly_weather_refresh_once(
            config=config,
            storage_dir=tmp_path,
            generated_at=daily_weather.datetime.fromisoformat("2026-06-25T20:30:00+00:00"),
        )
    )

    assert calls["fetch"] == 1
    assert result["report"]["headline"] == "Wrocław: wieczór, częściowe zachmurzenie i 27.5°C"


def test_hourly_weather_scheduler_refreshes_immediately_before_sleep(tmp_path, monkeypatch):
    daily_weather = load_daily_weather()
    config = daily_weather.DailyWeatherConfig(
        enabled=True,
        local_time=daily_weather.time(hour=7, minute=30),
        timezone_name="Europe/Warsaw",
        city="Wrocław",
        latitude=51.1079,
        longitude=17.0385,
    )
    calls = []
    sleeps = []

    class StopLoop(BaseException):
        pass

    async def fake_refresh_once(*, config, storage_dir, generated_at, force=False):
        calls.append(generated_at)
        return {"status": "refreshed", "report": {"id": "wroclaw-2026-06-25"}}

    async def stop_after_first_sleep(seconds):
        sleeps.append(seconds)
        raise StopLoop()

    monkeypatch.setattr(daily_weather, "run_hourly_weather_refresh_once", fake_refresh_once)

    with pytest.raises(StopLoop):
        asyncio.run(
            daily_weather.hourly_weather_scheduler_loop(
                config_factory=lambda: config,
                storage_dir=tmp_path,
                sleep=stop_after_first_sleep,
            )
        )

    assert len(calls) == 1
    assert sleeps and sleeps[0] > 0


def test_hourly_weather_scheduler_continues_after_refresh_error(tmp_path, monkeypatch):
    daily_weather = load_daily_weather()
    config = daily_weather.DailyWeatherConfig(
        enabled=True,
        local_time=daily_weather.time(hour=7, minute=30),
        timezone_name="Europe/Warsaw",
        city="Wrocław",
        latitude=51.1079,
        longitude=17.0385,
    )
    calls = {"refresh": 0, "sleep": 0}

    class StopLoop(BaseException):
        pass

    async def fake_refresh_once(*, config, storage_dir, generated_at, force=False):
        calls["refresh"] += 1
        if calls["refresh"] == 1:
            raise RuntimeError("Open-Meteo temporary outage")
        raise StopLoop()

    async def fast_sleep(seconds):
        calls["sleep"] += 1

    monkeypatch.setattr(daily_weather, "run_hourly_weather_refresh_once", fake_refresh_once)

    with pytest.raises(StopLoop):
        asyncio.run(
            daily_weather.hourly_weather_scheduler_loop(
                config_factory=lambda: config,
                storage_dir=tmp_path,
                sleep=fast_sleep,
            )
        )

    assert calls["refresh"] == 2
    assert calls["sleep"] >= 1


def test_latest_daily_weather_report_refreshes_stale_hour_cache(tmp_path, monkeypatch):
    daily_weather = load_daily_weather()
    config = daily_weather.DailyWeatherConfig(
        enabled=True,
        local_time=daily_weather.time(hour=7, minute=30),
        timezone_name="Europe/Warsaw",
        city="Wrocław",
        latitude=51.1079,
        longitude=17.0385,
    )
    (tmp_path / "last-daily-weather.json").write_text(
        json.dumps(
            {
                "lastReport": {
                    "id": "wroclaw-2026-06-25",
                    "city": "Wrocław",
                    "date": "2026-06-25",
                    "generatedAt": "2026-06-25T09:05:00+00:00",
                },
            }
        ),
        encoding="utf-8",
    )
    calls = {"fetch": 0}

    async def fake_fetch_daily_weather_report(*, config, generated_at):
        calls["fetch"] += 1
        return {
            "id": "wroclaw-2026-06-25",
            "city": config.city,
            "date": "2026-06-25",
            "generatedAt": generated_at.isoformat(),
        }

    monkeypatch.setattr(daily_weather, "fetch_daily_weather_report", fake_fetch_daily_weather_report)

    report = asyncio.run(
        daily_weather.latest_daily_weather_report(
            config=config,
            storage_dir=tmp_path,
            now=daily_weather.datetime.fromisoformat("2026-06-25T11:10:00+00:00"),
        )
    )

    assert calls["fetch"] == 1
    assert report["generatedAt"] == "2026-06-25T11:10:00+00:00"


def test_daily_weather_status_reports_hourly_refresh_fields(tmp_path):
    daily_weather = load_daily_weather()
    config = daily_weather.DailyWeatherConfig(
        enabled=True,
        local_time=daily_weather.time(hour=7, minute=30),
        timezone_name="Europe/Warsaw",
        city="Wrocław",
        latitude=51.1079,
        longitude=17.0385,
    )
    (tmp_path / "last-daily-weather.json").write_text(
        json.dumps(
            {
                "lastHourlyRefreshAt": "2026-06-25T11:05:00+00:00",
                "nextHourlyRefreshAt": "2026-06-25T14:00:00+02:00",
                "lastHourlyError": {"error": "temporary"},
            }
        ),
        encoding="utf-8",
    )

    status = daily_weather.daily_weather_status(storage_dir=tmp_path, config=config)

    assert status["lastHourlyRefreshAt"] == "2026-06-25T11:05:00+00:00"
    assert status["nextHourlyRefreshAt"] == "2026-06-25T14:00:00+02:00"
    assert status["lastHourlyError"] == {"error": "temporary"}


def test_daily_weather_status_reports_precipitation_schema_counts(tmp_path):
    daily_weather = load_daily_weather()
    config = daily_weather.DailyWeatherConfig(
        enabled=True,
        local_time=daily_weather.time(hour=7, minute=30),
        timezone_name="Europe/Warsaw",
        city="Wrocław",
        latitude=51.1079,
        longitude=17.0385,
    )
    precipitation_point = {
        "time": "2026-06-25T13:00",
        "probability": 70,
        "amount": 0.4,
        "rain": 0.4,
        "showers": 0,
        "snowfall": 0,
        "kind": "rain",
        "unit": "mm",
    }
    (tmp_path / "last-daily-weather.json").write_text(
        json.dumps(
            {
                "lastReport": {
                    "schemaVersion": 2,
                    "id": "wroclaw-2026-06-25",
                    "date": "2026-06-25",
                    "headline": "Wrocław: pogoda godzinowa",
                    "generatedAt": "2026-06-25T11:05:00+00:00",
                    "hourlyPrecipitation": [precipitation_point, {**precipitation_point, "time": "2026-06-25T14:00"}],
                    "precipitationTimeline": [precipitation_point],
                }
            }
        ),
        encoding="utf-8",
    )

    status = daily_weather.daily_weather_status(storage_dir=tmp_path, config=config)

    assert status["lastReport"]["weatherSchemaVersion"] == 2
    assert status["lastReport"]["hourlyPrecipitationCount"] == 2
    assert status["lastReport"]["precipitationTimelineCount"] == 1


def test_daily_weather_notifications_send_only_to_opted_in_devices():
    daily_weather = load_daily_weather()

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

    sender = FakeSender()
    report = {
        "id": "wroclaw-2026-06-25",
        "city": "Wrocław",
        "date": "2026-06-25",
        "weekday": "czwartek",
        "temperature": {"current": 21, "max": 26, "unit": "°C"},
        "conditions": {"label": "Częściowe zachmurzenie"},
        "nameDays": ["Łucja", "Wilhelm"],
    }

    summary = asyncio.run(
        daily_weather.send_daily_weather_notifications(
            devices={
                "weather-token": {"dailyWeatherEnabled": True},
                "files-only-token": {"dailyWeatherEnabled": False},
                "legacy-token": {},
            },
            report=report,
            sender=sender,
        )
    )

    assert summary["attempted"] == 1
    assert summary["sent"] == 1
    assert summary["skippedDevices"] == 2
    assert sender.calls[0]["deviceToken"] == "weather-token"
    assert sender.calls[0]["title"] == "Dzień dobry z Pavbot"
    assert sender.calls[0]["body"] == (
        "Miłego dnia! Prognoza dla: Wrocław — Częściowe zachmurzenie, "
        "21°C. Dotknij, aby zobaczyć Dzisiaj."
    )
    assert sender.calls[0]["userInfo"]["notificationKind"] == "dailyWeather"
    assert sender.calls[0]["userInfo"]["weatherDate"] == "2026-06-25"


def test_forced_daily_weather_send_does_not_consume_scheduled_run(tmp_path, monkeypatch):
    daily_weather = load_daily_weather()

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

    async def fake_fetch_daily_weather_report(*, config, generated_at):
        return {
            "id": "wroclaw-test",
            "city": config.city,
            "date": generated_at.astimezone(config.zoneinfo).date().isoformat(),
            "weekday": "sobota",
            "temperature": {"current": 19.3, "unit": "°C"},
            "conditions": {"label": "pochmurno"},
        }

    monkeypatch.setattr(daily_weather, "fetch_daily_weather_report", fake_fetch_daily_weather_report)
    (tmp_path / "devices.json").write_text(
        json.dumps({"weather-token": {"dailyWeatherEnabled": True}}),
        encoding="utf-8",
    )
    (tmp_path / "last-daily-weather.json").write_text(
        json.dumps(
            {
                "lastRunAt": "2026-06-26T05:30:00+00:00",
                "lastRunDate": "2026-06-26",
            }
        ),
        encoding="utf-8",
    )
    config = daily_weather.DailyWeatherConfig(
        enabled=True,
        local_time=daily_weather.parse_time("07:30"),
        timezone_name="Europe/Warsaw",
        city="Wrocław",
        latitude=51.1079,
        longitude=17.0385,
    )

    result = asyncio.run(
        daily_weather.run_daily_weather_once(
            config=config,
            storage_dir=tmp_path,
            sender=FakeSender(),
            force=True,
        )
    )
    state = json.loads((tmp_path / "last-daily-weather.json").read_text(encoding="utf-8"))

    assert result["status"] == "processed"
    assert state["lastRunDate"] == "2026-06-26"
    assert state["lastRunAt"] == "2026-06-26T05:30:00+00:00"
    assert state["lastForcedRunDate"] != state["lastRunDate"]
    assert state["lastDelivery"]["sent"] == 1
