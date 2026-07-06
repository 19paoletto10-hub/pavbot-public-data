from __future__ import annotations

import importlib.util
import json
from pathlib import Path


def load_publisher():
    module_path = Path(__file__).resolve().parents[1] / "scripts" / "publish_cloudkit_briefings.py"
    spec = importlib.util.spec_from_file_location("publish_cloudkit_briefings", module_path)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


def sample_manifest() -> dict:
    return {
        "schemaVersion": 1,
        "title": "Pavbot Automation Manifest",
        "generatedAt": "2026-07-05T17:00:00+00:00",
        "rawBaseUrl": "https://raw.githubusercontent.com/example/pavbot/main/",
        "automations": [],
        "topics": [
            {
                "slug": "aktualne-wydarzenia-mobile",
                "title": "Pavbot Aktualne",
                "path": "research/aktualne-wydarzenia-mobile",
                "topicFilePath": "",
                "url": "",
            }
        ],
        "artifacts": [
            {
                "id": "research/aktualne-wydarzenia-mobile/data/2026-07-05-1936-mobile-news.json",
                "type": "mobileNewsData",
                "topic": "aktualne-wydarzenia-mobile",
                "title": "Mobile news data",
                "path": "research/aktualne-wydarzenia-mobile/data/2026-07-05-1936-mobile-news.json",
                "url": "https://raw.githubusercontent.com/example/pavbot/main/research/aktualne-wydarzenia-mobile/data/2026-07-05-1936-mobile-news.json",
                "sizeBytes": 1234,
                "date": "2026-07-05",
                "time": "19:36",
            },
            {
                "id": "research/aktualne-wydarzenia-mobile/podcasts/2026-07-05-1936/audio/female-piper/podcast.mp3",
                "type": "podcastAudioVariant",
                "topic": "aktualne-wydarzenia-mobile",
                "title": "Podcast audio - female piper",
                "path": "research/aktualne-wydarzenia-mobile/podcasts/2026-07-05-1936/audio/female-piper/podcast.mp3",
                "url": "https://raw.githubusercontent.com/example/pavbot/main/research/aktualne-wydarzenia-mobile/podcasts/2026-07-05-1936/audio/female-piper/podcast.mp3",
                "sizeBytes": 2345,
                "date": "2026-07-05",
                "time": "19:36",
            },
        ],
    }


def manifest_with_two_topics() -> dict:
    manifest = sample_manifest()
    manifest["topics"] = manifest["topics"] + [
        {
            "slug": "tech-news",
            "title": "Tech News",
            "path": "research/tech-news",
            "topicFilePath": "",
            "url": "",
        }
    ]
    manifest["artifacts"] = manifest["artifacts"] + [
        {
            "id": "research/tech-news/runs/2026-07-05-1933.md",
            "type": "run",
            "topic": "tech-news",
            "title": "Tech News",
            "path": "research/tech-news/runs/2026-07-05-1933.md",
            "url": "https://raw.githubusercontent.com/example/pavbot/main/research/tech-news/runs/2026-07-05-1933.md",
            "sizeBytes": 1234,
            "date": "2026-07-05",
            "time": "19:33",
        },
        {
            "id": "research/tech-news/data/2026-07-05-1933-research.json",
            "type": "researchData",
            "topic": "tech-news",
            "title": "Research data",
            "path": "research/tech-news/data/2026-07-05-1933-research.json",
            "url": "https://raw.githubusercontent.com/example/pavbot/main/research/tech-news/data/2026-07-05-1933-research.json",
            "sizeBytes": 2345,
            "date": "2026-07-05",
            "time": "19:33",
        },
    ]
    return manifest


def test_build_briefing_records_from_manifest_uses_stable_record_ids_and_ready_status() -> None:
    publisher = load_publisher()

    records = publisher.build_briefing_records(
        sample_manifest(),
        manifest_url="https://raw.githubusercontent.com/example/pavbot/main/public/pavbot-manifest.json",
    )

    assert len(records) == 1
    record = records[0]
    assert record["recordName"] == "aktualne-wydarzenia-mobile:2026-07-05-1936"
    assert record["fields"]["briefingId"] == "aktualne-wydarzenia-mobile:2026-07-05-1936"
    assert record["fields"]["category"] == "aktualne-wydarzenia-mobile"
    assert record["fields"]["status"] == "ready"
    assert record["fields"]["manifestUrl"] == "https://raw.githubusercontent.com/example/pavbot/main/public/pavbot-manifest.json"
    assert record["fields"]["audioUrl"].endswith("/podcast.mp3")
    assert record["fields"]["version"] == 1


def test_build_briefing_records_can_scope_to_active_topic_only() -> None:
    publisher = load_publisher()

    records = publisher.build_briefing_records(
        manifest_with_two_topics(),
        manifest_url="https://raw.githubusercontent.com/example/pavbot/main/public/pavbot-manifest.json",
        topic_path="research/tech-news",
    )

    assert [record["recordName"] for record in records] == ["tech-news:2026-07-05-1933"]
    assert records[0]["fields"]["category"] == "tech-news"


def test_dry_run_topic_argument_outputs_only_active_topic_record(tmp_path, capsys) -> None:
    publisher = load_publisher()
    manifest_path = tmp_path / "pavbot-manifest.json"
    manifest_path.write_text(json.dumps(manifest_with_two_topics()), encoding="utf-8")

    exit_code = publisher.main(
        [
            "dry-run",
            "--manifest",
            str(manifest_path),
            "--manifest-url",
            "https://raw.githubusercontent.com/example/pavbot/main/public/pavbot-manifest.json",
            "--topic",
            "research/tech-news",
        ]
    )

    assert exit_code == 0
    output = json.loads(capsys.readouterr().out)
    assert [record["recordName"] for record in output["records"]] == ["tech-news:2026-07-05-1933"]


def test_preflight_queries_cloudkit_without_creating_records(tmp_path, monkeypatch, capsys) -> None:
    publisher = load_publisher()
    manifest_path = tmp_path / "pavbot-manifest.json"
    manifest_path.write_text(json.dumps(sample_manifest()), encoding="utf-8")
    calls: list[list[str]] = []

    def fake_run(command, text=False, capture_output=False, timeout=None):
        calls.append(command)
        return publisher.subprocess.CompletedProcess(command, 0, stdout='{"records":[]}', stderr="")

    monkeypatch.setattr(publisher.subprocess, "run", fake_run)

    exit_code = publisher.main(
        [
            "preflight",
            "--manifest",
            str(manifest_path),
            "--manifest-url",
            "https://raw.githubusercontent.com/example/pavbot/main/public/pavbot-manifest.json",
            "--topic",
            "research/aktualne-wydarzenia-mobile",
        ]
    )

    assert exit_code == 0
    output = json.loads(capsys.readouterr().out)
    assert output == {"status": "preflight-ok", "recordCount": 1}
    assert [command[2] for command in calls] == ["query-records"]
    assert not any("create-record" in command for command in calls)


def test_audio_url_ignores_podcast_brief_pdf_when_mp3_exists() -> None:
    publisher = load_publisher()
    manifest = sample_manifest()
    manifest["topics"] = [
        {
            "slug": "polska-swiat",
            "title": "Polska i Swiat",
            "path": "research/polska-swiat",
            "topicFilePath": "",
            "url": "",
        }
    ]
    manifest["artifacts"] = [
        {
            "id": "research/polska-swiat/podcasts/2026-07-05/brief.pdf",
            "type": "podcastBriefPdf",
            "topic": "polska-swiat",
            "title": "Podcast brief",
            "path": "research/polska-swiat/podcasts/2026-07-05/brief.pdf",
            "url": "https://raw.githubusercontent.com/example/pavbot/main/research/polska-swiat/podcasts/2026-07-05/brief.pdf",
            "date": "2026-07-05",
        },
        {
            "id": "research/polska-swiat/podcasts/2026-07-05/podcast.mp3",
            "type": "podcastAudio",
            "topic": "polska-swiat",
            "title": "Podcast audio",
            "path": "research/polska-swiat/podcasts/2026-07-05/podcast.mp3",
            "url": "https://raw.githubusercontent.com/example/pavbot/main/research/polska-swiat/podcasts/2026-07-05/podcast.mp3",
            "date": "2026-07-05",
        },
    ]

    records = publisher.build_briefing_records(
        manifest,
        manifest_url="https://raw.githubusercontent.com/example/pavbot/main/public/pavbot-manifest.json",
    )

    assert records[0]["fields"]["audioUrl"].endswith("/podcast.mp3")


def test_dry_run_outputs_records_without_requiring_cktool(tmp_path, capsys) -> None:
    publisher = load_publisher()
    manifest_path = tmp_path / "pavbot-manifest.json"
    manifest_path.write_text(json.dumps(sample_manifest()), encoding="utf-8")

    exit_code = publisher.main(
        [
            "dry-run",
            "--manifest",
            str(manifest_path),
            "--manifest-url",
            "https://raw.githubusercontent.com/example/pavbot/main/public/pavbot-manifest.json",
        ]
    )

    assert exit_code == 0
    output = json.loads(capsys.readouterr().out)
    assert output["status"] == "dry-run"
    assert output["records"][0]["recordName"] == "aktualne-wydarzenia-mobile:2026-07-05-1936"


def test_publish_replaces_existing_records_by_stable_briefing_id(monkeypatch) -> None:
    publisher = load_publisher()
    records = publisher.build_briefing_records(
        sample_manifest(),
        manifest_url="https://raw.githubusercontent.com/example/pavbot/main/public/pavbot-manifest.json",
    )
    calls: list[list[str]] = []

    def fake_run(command, check=False, text=False, capture_output=False, timeout=None):
        calls.append(command)
        if "query-records" in command:
            return publisher.subprocess.CompletedProcess(
                command,
                0,
                stdout=json.dumps(
                    {
                        "records": [
                            {
                                "recordName": "cktool-generated-name",
                                "fields": {
                                    "briefingId": {
                                        "type": "stringType",
                                        "value": "aktualne-wydarzenia-mobile:2026-07-05-1936",
                                    },
                                    "status": {"type": "stringType", "value": "ready"},
                                },
                            }
                        ]
                    }
                ),
                stderr="",
            )
        return publisher.subprocess.CompletedProcess(command, 0, stdout="{}", stderr="")

    monkeypatch.setattr(publisher.subprocess, "run", fake_run)

    publisher.publish_records(records, "iCloud.test", "production", "TEAM123")

    delete_calls = [command for command in calls if "delete-records" in command]
    create_calls = [command for command in calls if "create-record" in command]
    assert len(delete_calls) == 1
    assert len(create_calls) == 1
    assert "briefingId == aktualne-wydarzenia-mobile:2026-07-05-1936" in delete_calls[0]
    assert "--dry-run" in delete_calls[0]
    assert "false" in delete_calls[0]
    assert "--team-id" in create_calls[0]
    assert "TEAM123" in create_calls[0]


def test_verify_requires_ready_record_fields_not_raw_stdout_text(monkeypatch) -> None:
    publisher = load_publisher()
    records = publisher.build_briefing_records(
        sample_manifest(),
        manifest_url="https://raw.githubusercontent.com/example/pavbot/main/public/pavbot-manifest.json",
    )
    calls: list[list[str]] = []

    def fake_run(command, text=False, capture_output=False, timeout=None):
        calls.append(command)
        return publisher.subprocess.CompletedProcess(
            command,
            0,
            stdout=json.dumps(
                {
                    "records": [
                        {
                            "recordName": "some-record",
                            "fields": {
                                "briefingId": {
                                    "type": "stringType",
                                    "value": "aktualne-wydarzenia-mobile:2026-07-05-1936",
                                },
                                "status": {"type": "stringType", "value": "draft"},
                                "note": {"type": "stringType", "value": "ready appears only here"},
                            },
                        }
                    ]
                }
            ),
            stderr="",
        )

    monkeypatch.setattr(publisher.subprocess, "run", fake_run)

    try:
        publisher.verify_records(records, "iCloud.test", "production", "TEAM123")
    except RuntimeError as error:
        assert "CloudKit verification missing ready records" in str(error)
    else:
        raise AssertionError("verify_records must fail when status field is not ready")

    assert calls
    assert "briefingId == aktualne-wydarzenia-mobile:2026-07-05-1936" in calls[0]
    assert "status == ready" not in calls[0]
    assert "--requested-fields" not in calls[0]


def test_verify_requires_current_manifest_url_and_category(monkeypatch) -> None:
    publisher = load_publisher()
    records = publisher.build_briefing_records(
        sample_manifest(),
        manifest_url="https://raw.githubusercontent.com/example/pavbot/main/public/pavbot-manifest.json",
    )

    def fake_run(command, text=False, capture_output=False, timeout=None):
        return publisher.subprocess.CompletedProcess(
            command,
            0,
            stdout=json.dumps(
                {
                    "records": [
                        {
                            "recordName": "stale-record",
                            "fields": {
                                "briefingId": {
                                    "type": "stringType",
                                    "value": "aktualne-wydarzenia-mobile:2026-07-05-1936",
                                },
                                "status": {"type": "stringType", "value": "ready"},
                                "manifestUrl": {
                                    "type": "stringType",
                                    "value": "https://raw.githubusercontent.com/example/old/main/public/pavbot-manifest.json",
                                },
                                "category": {"type": "stringType", "value": "aktualne-wydarzenia-mobile"},
                            },
                        }
                    ]
                }
            ),
            stderr="",
        )

    monkeypatch.setattr(publisher.subprocess, "run", fake_run)

    try:
        publisher.verify_records(records, "iCloud.test", "production", "TEAM123")
    except RuntimeError as error:
        assert "CloudKit verification missing ready records" in str(error)
    else:
        raise AssertionError("verify_records must fail when manifestUrl is stale")


def test_validate_publisher_config_rejects_wrong_production_values(tmp_path, capsys) -> None:
    publisher = load_publisher()
    manifest_path = tmp_path / "pavbot-manifest.json"
    manifest_path.write_text(json.dumps(sample_manifest()), encoding="utf-8")

    exit_code = publisher.main(
        [
            "dry-run",
            "--manifest",
            str(manifest_path),
            "--manifest-url",
            "https://raw.githubusercontent.com/example/pavbot/main/public/pavbot-manifest.json",
            "--container-id",
            "iCloud.wrong.container",
            "--environment",
            "production",
            "--team-id",
            "WRONGTEAM",
            "--topic",
            "research/aktualne-wydarzenia-mobile",
        ]
    )

    captured = capsys.readouterr()
    assert exit_code == 1
    assert "expected iCloud.com.paweltanski.pavbotviewer" in captured.err
    assert "expected SP774TZZU8" in captured.err


def test_run_cktool_uses_configured_timeout(monkeypatch) -> None:
    publisher = load_publisher()
    calls = []

    def fake_run(command, text=False, capture_output=False, timeout=None):
        calls.append({"command": command, "timeout": timeout})
        return publisher.subprocess.CompletedProcess(command, 0, stdout='{"records":[]}', stderr="")

    monkeypatch.setenv("PAVBOT_CLOUDKIT_TIMEOUT_SECONDS", "12")
    monkeypatch.setattr(publisher.subprocess, "run", fake_run)

    publisher.run_cktool(["xcrun", "cktool", "query-records"])

    assert calls == [{"command": ["xcrun", "cktool", "query-records"], "timeout": 12}]


def test_verify_fails_fast_when_cktool_token_is_missing(monkeypatch) -> None:
    publisher = load_publisher()
    records = publisher.build_briefing_records(
        sample_manifest(),
        manifest_url="https://raw.githubusercontent.com/example/pavbot/main/public/pavbot-manifest.json",
    )

    def fake_run(command, text=False, capture_output=False, timeout=None):
        return publisher.subprocess.CompletedProcess(
            command,
            1,
            stdout="",
            stderr="Error: No user token found in arguments, CLOUDKIT_USER_TOKEN environment variable, or built-in methods. (See: save-token)",
        )

    monkeypatch.setattr(publisher.subprocess, "run", fake_run)

    try:
        publisher.verify_records(records, "iCloud.test", "production", "TEAM123")
    except RuntimeError as error:
        assert "xcrun cktool save-token" in str(error)
    else:
        raise AssertionError("verify_records must fail fast when cktool auth is missing")


def test_verify_fails_fast_when_cktool_token_is_expired(monkeypatch) -> None:
    publisher = load_publisher()
    records = publisher.build_briefing_records(
        sample_manifest(),
        manifest_url="https://raw.githubusercontent.com/example/pavbot/main/public/pavbot-manifest.json",
    )

    def fake_run(command, text=False, capture_output=False, timeout=None):
        return publisher.subprocess.CompletedProcess(
            command,
            1,
            stdout="",
            stderr="Authentication failed. User token may have been entered incorrectly or has expired.",
        )

    monkeypatch.setattr(publisher.subprocess, "run", fake_run)

    try:
        publisher.verify_records(records, "iCloud.test", "production", "TEAM123")
    except RuntimeError as error:
        assert "xcrun cktool save-token" in str(error)
    else:
        raise AssertionError("verify_records must fail fast when cktool auth is expired")
