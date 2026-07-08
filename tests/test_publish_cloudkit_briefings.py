from __future__ import annotations

import argparse
import importlib
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace


REPO_ROOT = Path(__file__).resolve().parents[1]
SCRIPT_PATH = REPO_ROOT / "scripts" / "publish_cloudkit_briefings.py"


class PublishCloudKitBriefingsTest(unittest.TestCase):
    def load_publisher_module(self):
        sys.path.insert(0, str(REPO_ROOT / "scripts"))
        try:
            return importlib.import_module("publish_cloudkit_briefings")
        finally:
            sys.path.pop(0)

    def test_build_notification_payload_matches_ios_apns_contract(self) -> None:
        publish_cloudkit_briefings = self.load_publisher_module()

        record = {
            "fields": {
                "briefingId": "pavbot-puls-dnia-news-3h:2026-07-06-1800",
                "category": "puls-dnia-news",
                "title": "Pavbot Puls Dnia 3h · 2026-07-06 18:00",
                "manifestUrl": (
                    "https://raw.githubusercontent.com/19paoletto10-hub/"
                    "pavbot-public-data/main/public/pavbot-manifest.json"
                ),
            }
        }

        self.assertEqual(
            publish_cloudkit_briefings.build_notification_payload(record),
            {
                "aps": {
                    "alert": {
                        "title": "Pavbot",
                        "subtitle": "Pavbot Puls Dnia 3h · 2026-07-06 18:00",
                        "body": "Nowe dane: Pavbot Puls Dnia 3h · 2026-07-06 18:00",
                    },
                    "sound": "default",
                },
                "briefingId": "pavbot-puls-dnia-news-3h:2026-07-06-1800",
                "category": "puls-dnia-news",
                "manifestUrl": (
                    "https://raw.githubusercontent.com/19paoletto10-hub/"
                    "pavbot-public-data/main/public/pavbot-manifest.json"
                ),
            },
        )

    def test_cktool_base_args_use_single_production_environment_flag(self) -> None:
        publish_cloudkit_briefings = self.load_publisher_module()
        args = argparse.Namespace(
            team_id="SP774TZZU8",
            container_id="iCloud.com.paweltanski.pavbotviewer",
            environment="production",
        )

        command = publish_cloudkit_briefings.cktool_base_args(args, "query-records")

        self.assertEqual(command.count("--environment"), 1)
        self.assertEqual(command[command.index("--environment") + 1], "production")
        self.assertEqual(command.count("--database-type"), 1)
        self.assertEqual(command[command.index("--database-type") + 1], "public")

    def test_cktool_schema_hint_explains_missing_artifact_record_type(self) -> None:
        publish_cloudkit_briefings = self.load_publisher_module()

        hint = publish_cloudkit_briefings.cktool_schema_hint(
            "An unknown error occured with message: not-found.",
            ["xcrun", "cktool", "query-records", "--record-type", "Artifact"],
        )

        self.assertIsNotNone(hint)
        self.assertIn("Artifact record type", hint)
        self.assertIn("scripts/pavbot_commit_and_push_outputs.sh --all-topics", hint)

    def test_cloudkit_web_services_client_signs_query_requests(self) -> None:
        publish_cloudkit_briefings = self.load_publisher_module()
        requests = []

        with tempfile.TemporaryDirectory() as tmp:
            key_path = Path(tmp) / "cloudkit-server-key.pem"
            subprocess.run(
                ["openssl", "ecparam", "-name", "prime256v1", "-genkey", "-noout", "-out", str(key_path)],
                check=True,
                capture_output=True,
            )
            args = SimpleNamespace(
                container_id="iCloud.com.paweltanski.pavbotviewer",
                environment="production",
                cloudkit_auth_mode="server-to-server",
                server_key_id="server-key-id",
                server_private_key_path=str(key_path),
            )

            class FakeResponse:
                def __enter__(self):
                    return self

                def __exit__(self, *_exc):
                    return False

                def read(self):
                    return b'{"records":[]}'

            original_urlopen = publish_cloudkit_briefings.urllib.request.urlopen

            def fake_urlopen(request, *, timeout):
                requests.append((request, timeout))
                return FakeResponse()

            publish_cloudkit_briefings.urllib.request.urlopen = fake_urlopen
            try:
                records = publish_cloudkit_briefings.CloudKitWebServicesClient(args).query_records_by_type("Briefing")
            finally:
                publish_cloudkit_briefings.urllib.request.urlopen = original_urlopen

        self.assertEqual(records, [])
        self.assertEqual(len(requests), 1)
        request, timeout = requests[0]
        self.assertEqual(timeout, publish_cloudkit_briefings.DEFAULT_CKTOOL_TIMEOUT_SECONDS)
        self.assertEqual(
            request.full_url,
            "https://api.apple-cloudkit.com/database/1/iCloud.com.paweltanski.pavbotviewer/production/public/records/query",
        )
        self.assertEqual(request.headers["X-apple-cloudkit-request-keyid"], "server-key-id")
        self.assertIn("X-apple-cloudkit-request-iso8601date", request.headers)
        self.assertIn("X-apple-cloudkit-request-signaturev1", request.headers)
        body = json.loads(request.data.decode("utf-8"))
        self.assertEqual(body["query"]["recordType"], "Briefing")
        self.assertEqual(body["resultsLimit"], 200)
        self.assertNotIn("EC PRIVATE KEY", request.headers["X-apple-cloudkit-request-signaturev1"])

    def test_query_records_by_type_uses_server_to_server_backend_when_configured(self) -> None:
        publish_cloudkit_briefings = self.load_publisher_module()
        args = SimpleNamespace(
            cloudkit_auth_mode="server-to-server",
            server_key_id="server-key-id",
            server_private_key_path="/tmp/cloudkit-server-key.pem",
        )
        calls: list[str] = []
        original_client = publish_cloudkit_briefings.CloudKitWebServicesClient
        original_run = publish_cloudkit_briefings.run_cktool

        class FakeClient:
            def __init__(self, _args):
                pass

            def query_records_by_type(self, record_type):
                calls.append(record_type)
                return [{"recordName": "from-web-services"}]

        def fail_run_cktool(command):
            self.fail(f"server-to-server mode should not call cktool: {command}")

        publish_cloudkit_briefings.CloudKitWebServicesClient = FakeClient
        publish_cloudkit_briefings.run_cktool = fail_run_cktool
        try:
            records = publish_cloudkit_briefings.query_records_by_type("Briefing", args)
        finally:
            publish_cloudkit_briefings.CloudKitWebServicesClient = original_client
            publish_cloudkit_briefings.run_cktool = original_run

        self.assertEqual(calls, ["Briefing"])
        self.assertEqual(records, [{"recordName": "from-web-services"}])

    def test_load_cloudkit_local_env_sets_missing_values_only(self) -> None:
        publish_cloudkit_briefings = self.load_publisher_module()
        original_auth_mode = os.environ.get("PAVBOT_CLOUDKIT_AUTH_MODE")
        original_key_id = os.environ.get("PAVBOT_CLOUDKIT_SERVER_KEY_ID")
        try:
            os.environ["PAVBOT_CLOUDKIT_AUTH_MODE"] = "cktool"
            os.environ.pop("PAVBOT_CLOUDKIT_SERVER_KEY_ID", None)
            with tempfile.TemporaryDirectory() as tmp:
                env_path = Path(tmp) / "cloudkit.env"
                env_path.write_text(
                    "\n".join(
                        [
                            "PAVBOT_CLOUDKIT_AUTH_MODE=server-to-server",
                            "PAVBOT_CLOUDKIT_SERVER_KEY_ID=server-key-id",
                        ]
                    )
                    + "\n",
                    encoding="utf-8",
                )

                publish_cloudkit_briefings.load_cloudkit_local_env(env_path)

            self.assertEqual(os.environ["PAVBOT_CLOUDKIT_AUTH_MODE"], "cktool")
            self.assertEqual(os.environ["PAVBOT_CLOUDKIT_SERVER_KEY_ID"], "server-key-id")
        finally:
            if original_auth_mode is None:
                os.environ.pop("PAVBOT_CLOUDKIT_AUTH_MODE", None)
            else:
                os.environ["PAVBOT_CLOUDKIT_AUTH_MODE"] = original_auth_mode
            if original_key_id is None:
                os.environ.pop("PAVBOT_CLOUDKIT_SERVER_KEY_ID", None)
            else:
                os.environ["PAVBOT_CLOUDKIT_SERVER_KEY_ID"] = original_key_id

    def test_publish_records_performs_real_cloudkit_create_or_replace(self) -> None:
        publish_cloudkit_briefings = self.load_publisher_module()
        args = argparse.Namespace(
            team_id="SP774TZZU8",
            container_id="iCloud.com.paweltanski.pavbotviewer",
            environment="production",
        )
        record = {
            "recordType": "Briefing",
            "recordName": "puls-dnia-news:2026-07-06-1800",
            "fields": {
                "briefingId": "puls-dnia-news:2026-07-06-1800",
                "title": "Pavbot Puls Dnia News · 2026-07-06 18:00",
                "summary": "Gotowe.",
                "manifestUrl": "https://raw.githubusercontent.com/19paoletto10-hub/pavbot-public-data/main/public/pavbot-manifest.json",
                "createdAt": "2026-07-06T18:00:00+00:00",
                "locale": "pl-PL",
                "category": "puls-dnia-news",
                "status": "ready",
                "version": 1,
            },
        }
        calls: list[list[str]] = []
        original_query = publish_cloudkit_briefings.query_existing_records
        original_run = publish_cloudkit_briefings.run_cktool

        def fake_query_existing_records(_record, _args):
            return [{"recordName": "existing-briefing-record"}]

        def fake_run_cktool(command):
            calls.append(command)
            return subprocess.CompletedProcess(command, 0, stdout='{"records":[]}', stderr="")

        publish_cloudkit_briefings.query_existing_records = fake_query_existing_records
        publish_cloudkit_briefings.run_cktool = fake_run_cktool
        try:
            publish_cloudkit_briefings.publish_records([record], args)
        finally:
            publish_cloudkit_briefings.query_existing_records = original_query
            publish_cloudkit_briefings.run_cktool = original_run

        self.assertEqual([call[2] for call in calls], ["delete-record", "create-record"])
        self.assertIn("--record-name", calls[0])
        self.assertIn("existing-briefing-record", calls[0])
        self.assertIn("--record-type", calls[1])
        self.assertIn("--fields-json", calls[1])
        created_fields = json.loads(calls[1][calls[1].index("--fields-json") + 1])
        self.assertEqual(created_fields["briefingId"]["value"], "puls-dnia-news:2026-07-06-1800")
        self.assertEqual(created_fields["category"]["value"], "puls-dnia-news")
        self.assertEqual(created_fields["status"]["value"], "ready")

    def test_publish_records_skips_existing_record_when_fields_match(self) -> None:
        publish_cloudkit_briefings = self.load_publisher_module()
        args = argparse.Namespace(
            team_id="SP774TZZU8",
            container_id="iCloud.com.paweltanski.pavbotviewer",
            environment="production",
        )
        record = {
            "recordType": "Briefing",
            "fields": {
                "briefingId": "puls-dnia-news:2026-07-06-1800",
                "title": "Pavbot Puls Dnia News · 2026-07-06 18:00",
                "status": "ready",
                "version": 1,
            },
        }
        original_query = publish_cloudkit_briefings.query_existing_records
        original_run = publish_cloudkit_briefings.run_cktool

        def fake_query_existing_records(_record, _args):
            return [
                {
                    "recordName": "existing-briefing-record",
                    "fields": {
                        "briefingId": {"value": "puls-dnia-news:2026-07-06-1800"},
                        "title": {"value": "Pavbot Puls Dnia News · 2026-07-06 18:00"},
                        "status": {"value": "ready"},
                        "version": {"value": 1},
                    },
                }
            ]

        def fail_run_cktool(command):
            self.fail(f"matching CloudKit record should not be recreated: {command}")

        publish_cloudkit_briefings.query_existing_records = fake_query_existing_records
        publish_cloudkit_briefings.run_cktool = fail_run_cktool
        try:
            publish_cloudkit_briefings.publish_records([record], args)
        finally:
            publish_cloudkit_briefings.query_existing_records = original_query
            publish_cloudkit_briefings.run_cktool = original_run

    def test_all_topics_backfill_creates_missing_briefings_only(self) -> None:
        publish_cloudkit_briefings = self.load_publisher_module()
        args = argparse.Namespace(
            team_id="SP774TZZU8",
            container_id="iCloud.com.paweltanski.pavbotviewer",
            environment="production",
        )
        existing_briefing = {
            "recordType": "Briefing",
            "fields": {
                "briefingId": "puls-dnia-news:2026-07-06-1800",
                "title": "Pavbot Puls Dnia News · 2026-07-06 18:00",
                "summary": "Gotowe.",
                "manifestUrl": "https://raw.githubusercontent.com/19paoletto10-hub/pavbot-public-data/main/public/pavbot-manifest.json",
                "createdAt": "2026-07-06T18:00:00+00:00",
                "locale": "pl-PL",
                "category": "puls-dnia-news",
                "status": "ready",
                "version": 1,
            },
        }
        missing_briefing = {
            "recordType": "Briefing",
            "fields": {
                "briefingId": "llm-ai-jobs-wroclaw:2026-07-07-1732",
                "title": "LLM AI Jobs Wroclaw · 2026-07-07 17:32",
                "summary": "Gotowe.",
                "manifestUrl": "https://raw.githubusercontent.com/19paoletto10-hub/pavbot-public-data/main/public/pavbot-manifest.json",
                "createdAt": "2026-07-07T17:32:00+00:00",
                "locale": "pl-PL",
                "category": "llm-ai-jobs-wroclaw",
                "status": "ready",
                "version": 1,
            },
        }
        calls: list[str] = []
        original_query_type = publish_cloudkit_briefings.query_records_by_type
        original_query_existing = publish_cloudkit_briefings.query_existing_records
        original_run = publish_cloudkit_briefings.run_cktool

        publish_cloudkit_briefings.query_records_by_type = lambda _record_type, _args: []

        def fake_query_existing_records(record, _args):
            if record["recordType"] == "Briefing" and record["fields"]["briefingId"] == existing_briefing["fields"]["briefingId"]:
                return [{"recordName": "existing-briefing-record", "fields": {"briefingId": {"value": existing_briefing["fields"]["briefingId"]}}}]
            return []

        def fake_run_cktool(command):
            if command[2] == "create-record":
                calls.append(command[command.index("--record-type") + 1])
            return subprocess.CompletedProcess(command, 0, stdout='{"records":[]}', stderr="")

        publish_cloudkit_briefings.query_existing_records = fake_query_existing_records
        publish_cloudkit_briefings.run_cktool = fake_run_cktool
        try:
            publish_cloudkit_briefings.publish_publication_records(
                [existing_briefing, missing_briefing],
                [],
                args,
                replace_briefings=False,
            )
        finally:
            publish_cloudkit_briefings.query_records_by_type = original_query_type
            publish_cloudkit_briefings.query_existing_records = original_query_existing
            publish_cloudkit_briefings.run_cktool = original_run

        self.assertEqual(calls, ["Briefing"])

    def test_query_existing_records_filters_cktool_results_locally(self) -> None:
        publish_cloudkit_briefings = self.load_publisher_module()
        args = argparse.Namespace(
            team_id="SP774TZZU8",
            container_id="iCloud.com.paweltanski.pavbotviewer",
            environment="production",
        )
        record = {
            "recordType": "Briefing",
            "fields": {"briefingId": "puls-dnia-news:2026-07-07-2105"},
        }
        original_run = publish_cloudkit_briefings.run_cktool

        def fake_run_cktool(command):
            self.assertNotIn("--filters", command)
            return subprocess.CompletedProcess(
                command,
                0,
                stdout=json.dumps(
                    {
                        "records": [
                            {
                                "recordName": "other-record",
                                "fields": {"briefingId": {"value": "reddit-radar:2026-07-07-1808"}},
                            },
                            {
                                "recordName": "pulse-record",
                                "fields": {"briefingId": {"value": "puls-dnia-news:2026-07-07-2105"}},
                            },
                        ]
                    }
                ),
                stderr="",
            )

        publish_cloudkit_briefings.run_cktool = fake_run_cktool
        try:
            matches = publish_cloudkit_briefings.query_existing_records(record, args)
        finally:
            publish_cloudkit_briefings.run_cktool = original_run

        self.assertEqual([item["recordName"] for item in matches], ["pulse-record"])

    def test_verify_records_retries_until_cloudkit_query_catches_up(self) -> None:
        publish_cloudkit_briefings = self.load_publisher_module()
        args = argparse.Namespace(
            team_id="SP774TZZU8",
            container_id="iCloud.com.paweltanski.pavbotviewer",
            environment="production",
        )
        record = {
            "recordType": "Briefing",
            "fields": {"briefingId": "puls-dnia-news:2026-07-07-2105"},
        }
        calls = 0
        original_query = publish_cloudkit_briefings.query_existing_records
        original_sleep = publish_cloudkit_briefings.time.sleep

        def fake_query_existing_records(_record, _args):
            nonlocal calls
            calls += 1
            return [] if calls == 1 else [{"recordName": "pulse-record"}]

        publish_cloudkit_briefings.query_existing_records = fake_query_existing_records
        publish_cloudkit_briefings.time.sleep = lambda _seconds: None
        try:
            publish_cloudkit_briefings.verify_records([record], args)
        finally:
            publish_cloudkit_briefings.query_existing_records = original_query
            publish_cloudkit_briefings.time.sleep = original_sleep

        self.assertEqual(calls, 2)

    def test_publish_publication_records_writes_artifacts_before_briefing(self) -> None:
        publish_cloudkit_briefings = self.load_publisher_module()
        args = argparse.Namespace(
            team_id="SP774TZZU8",
            container_id="iCloud.com.paweltanski.pavbotviewer",
            environment="production",
        )
        briefing = {
            "recordType": "Briefing",
            "fields": {
                "briefingId": "puls-dnia-news:2026-07-06-1800",
                "title": "Pavbot Puls Dnia News · 2026-07-06 18:00",
                "summary": "Gotowe.",
                "manifestUrl": "https://raw.githubusercontent.com/19paoletto10-hub/pavbot-public-data/main/public/pavbot-manifest.json",
                "createdAt": "2026-07-06T18:00:00+00:00",
                "locale": "pl-PL",
                "category": "puls-dnia-news",
                "status": "ready",
                "version": 1,
            },
        }
        artifact = {
            "recordType": "Artifact",
            "fields": {
                "artifactId": "research/puls-dnia-news/data/2026-07-06-1800-pulse-news.json",
                "briefingId": "puls-dnia-news:2026-07-06-1800",
                "path": "research/puls-dnia-news/data/2026-07-06-1800-pulse-news.json",
                "createdAt": "2026-07-06T18:00:00+00:00",
                "status": "ready",
                "version": 1,
            },
        }
        calls: list[str] = []
        original_query_type = publish_cloudkit_briefings.query_records_by_type
        original_query_existing = publish_cloudkit_briefings.query_existing_records
        original_run = publish_cloudkit_briefings.run_cktool

        publish_cloudkit_briefings.query_records_by_type = lambda _record_type, _args: []
        publish_cloudkit_briefings.query_existing_records = lambda _record, _args: []

        def fake_run_cktool(command):
            if command[2] == "create-record":
                calls.append(command[command.index("--record-type") + 1])
            return subprocess.CompletedProcess(command, 0, stdout='{"records":[]}', stderr="")

        publish_cloudkit_briefings.run_cktool = fake_run_cktool
        try:
            publish_cloudkit_briefings.publish_publication_records([briefing], [artifact], args)
        finally:
            publish_cloudkit_briefings.query_records_by_type = original_query_type
            publish_cloudkit_briefings.query_existing_records = original_query_existing
            publish_cloudkit_briefings.run_cktool = original_run

        self.assertEqual(calls, ["Artifact", "Briefing"])

    def test_verify_publication_records_fails_when_artifact_set_is_incomplete(self) -> None:
        publish_cloudkit_briefings = self.load_publisher_module()
        args = argparse.Namespace(
            team_id="SP774TZZU8",
            container_id="iCloud.com.paweltanski.pavbotviewer",
            environment="production",
        )
        briefing = {
            "recordType": "Briefing",
            "fields": {"briefingId": "puls-dnia-news:2026-07-06-1800"},
        }
        artifact = {
            "recordType": "Artifact",
            "fields": {
                "artifactId": "research/puls-dnia-news/data/2026-07-06-1800-pulse-news.json",
                "briefingId": "puls-dnia-news:2026-07-06-1800",
                "path": "research/puls-dnia-news/data/2026-07-06-1800-pulse-news.json",
            },
        }
        original_query_existing = publish_cloudkit_briefings.query_existing_records
        original_query_type = publish_cloudkit_briefings.query_records_by_type

        def fake_query_existing_records(record, _args):
            return [{"recordName": "existing"}]

        def fake_query_records_by_type(record_type, _args):
            if record_type == "Artifact":
                return []
            return [{"recordName": "briefing", "fields": {"briefingId": {"value": "puls-dnia-news:2026-07-06-1800"}}}]

        publish_cloudkit_briefings.query_existing_records = fake_query_existing_records
        publish_cloudkit_briefings.query_records_by_type = fake_query_records_by_type
        try:
            with self.assertRaises(publish_cloudkit_briefings.CloudKitVerificationError) as context:
                publish_cloudkit_briefings.verify_publication_records([briefing], [artifact], args)
        finally:
            publish_cloudkit_briefings.query_existing_records = original_query_existing
            publish_cloudkit_briefings.query_records_by_type = original_query_type

        self.assertIn("Artifact records do not match", str(context.exception))

    def test_build_records_split_same_topic_stamp_by_automation(self) -> None:
        publish_cloudkit_briefings = self.load_publisher_module()
        manifest = {
            "schemaVersion": 1,
            "topics": [
                {"slug": "tech-news", "title": "Pavbot Tech News"},
            ],
            "automations": [
                {
                    "id": "codex-agent-automation-daily-research",
                    "name": "Pavbot Tech Research 08:00",
                    "kind": "research",
                    "topic": "tech-news",
                    "topicPath": "research/tech-news",
                },
                {
                    "id": "pavbot-tech-podcast-09-00",
                    "name": "Pavbot Tech Podcast 09:00",
                    "kind": "podcast",
                    "topic": "tech-news",
                    "topicPath": "research/tech-news",
                    "output": "research/tech-news/podcasts/YYYY-MM-DD/podcast.mp3",
                },
            ],
            "artifacts": [
                {
                    "id": "tech-run",
                    "topic": "tech-news",
                    "type": "run",
                    "title": "Tech run",
                    "path": "research/tech-news/runs/2026-07-08.md",
                    "url": "research/tech-news/runs/2026-07-08.md",
                    "sizeBytes": 42,
                    "date": "2026-07-08",
                },
                {
                    "id": "tech-podcast",
                    "topic": "tech-news",
                    "type": "podcastAudio",
                    "title": "Podcast audio",
                    "path": "research/tech-news/podcasts/2026-07-08/podcast.mp3",
                    "url": "research/tech-news/podcasts/2026-07-08/podcast.mp3",
                    "sizeBytes": 100,
                    "date": "2026-07-08",
                },
            ],
        }

        briefings = publish_cloudkit_briefings.build_briefing_records(
            manifest,
            "https://raw.githubusercontent.com/example/pavbot/main/public/pavbot-manifest.json",
            "research/tech-news",
        )
        artifacts = publish_cloudkit_briefings.build_artifact_records(
            manifest,
            "https://raw.githubusercontent.com/example/pavbot/main/public/pavbot-manifest.json",
            "research/tech-news",
        )

        by_id = {record["fields"]["briefingId"]: record for record in briefings}
        self.assertEqual(
            sorted(by_id),
            [
                "codex-agent-automation-daily-research:2026-07-08",
                "pavbot-tech-podcast-09-00:2026-07-08",
            ],
        )
        self.assertEqual(by_id["codex-agent-automation-daily-research:2026-07-08"]["fields"]["title"], "Pavbot Tech Research 08:00 · 2026-07-08")
        self.assertEqual(by_id["pavbot-tech-podcast-09-00:2026-07-08"]["fields"]["title"], "Pavbot Tech Podcast 09:00 · 2026-07-08")
        self.assertEqual(
            {
                artifact["fields"]["path"]: artifact["fields"]["briefingId"]
                for artifact in artifacts
            },
            {
                "research/tech-news/runs/2026-07-08.md": "codex-agent-automation-daily-research:2026-07-08",
                "research/tech-news/podcasts/2026-07-08/podcast.mp3": "pavbot-tech-podcast-09-00:2026-07-08",
            },
        )

    def test_run_cktool_reports_actionable_hint_for_expired_user_token(self) -> None:
        publish_cloudkit_briefings = self.load_publisher_module()
        original_run = publish_cloudkit_briefings.subprocess.run

        def fake_run(*_args, **_kwargs):
            return subprocess.CompletedProcess(
                ["xcrun", "cktool", "query-records"],
                1,
                stdout="",
                stderr=(
                    "❌ An error occurred while performing the command.\n"
                    "Session has expired or is invalid. A new user token may be required."
                ),
            )

        publish_cloudkit_briefings.subprocess.run = fake_run
        try:
            with self.assertRaises(publish_cloudkit_briefings.CktoolCommandError) as context:
                publish_cloudkit_briefings.run_cktool(["xcrun", "cktool", "query-records"])
        finally:
            publish_cloudkit_briefings.subprocess.run = original_run

        message = str(context.exception)
        self.assertIn("xcrun cktool save-token --type user --method keychain --force", message)
        self.assertIn("unset CLOUDKIT_USER_TOKEN CLOUDKIT_MANAGEMENT_TOKEN PAVBOT_CLOUDKIT_DRY_RUN", message)

    def test_dry_run_emits_notification_payload_for_selected_topic_only(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            manifest_path = Path(tmp) / "pavbot-manifest.json"
            manifest_path.write_text(
                json.dumps(
                    {
                        "schemaVersion": 1,
                        "automations": [
                            {
                                "id": "pavbot-puls-dnia-news-3h",
                                "name": "Pavbot Puls Dnia 3h",
                                "kind": "automation",
                                "topic": "puls-dnia-news",
                                "topicPath": "research/puls-dnia-news",
                                "output": "research/puls-dnia-news/data/YYYY-MM-DD-HHMM-pulse-news.json",
                            }
                        ],
                        "topics": [
                            {"slug": "puls-dnia-news", "title": "Pavbot Puls Dnia News"},
                            {"slug": "tech-news", "title": "Pavbot Tech News"},
                        ],
                        "artifacts": [
                            {
                                "id": "pulse-data",
                                "topic": "puls-dnia-news",
                                "type": "pulseNewsData",
                                "title": "Puls data",
                                "path": "research/puls-dnia-news/data/2026-07-06-1800-pulse-news.json",
                                "url": "research/puls-dnia-news/data/2026-07-06-1800-pulse-news.json",
                                "date": "2026-07-06",
                                "time": "18:00",
                            },
                            {
                                "id": "tech-run",
                                "topic": "tech-news",
                                "type": "run",
                                "title": "Tech run",
                                "path": "research/tech-news/runs/2026-07-06.md",
                                "url": "research/tech-news/runs/2026-07-06.md",
                                "date": "2026-07-06",
                            },
                        ],
                    }
                ),
                encoding="utf-8",
            )

            result = subprocess.run(
                [
                    sys.executable,
                    str(SCRIPT_PATH),
                    "dry-run",
                    "--manifest",
                    str(manifest_path),
                    "--topic",
                    "research/puls-dnia-news",
                ],
                cwd=REPO_ROOT,
                text=True,
                capture_output=True,
                check=False,
            )

        self.assertEqual(result.returncode, 0, result.stderr)
        payload = json.loads(result.stdout)
        self.assertEqual([record["fields"]["category"] for record in payload["records"]], ["puls-dnia-news"])
        self.assertEqual(payload["records"][0]["notificationPayload"]["briefingId"], "pavbot-puls-dnia-news-3h:2026-07-06-1800")
        self.assertEqual(payload["records"][0]["notificationPayload"]["category"], "puls-dnia-news")
        self.assertEqual(
            payload["records"][0]["notificationPayload"]["manifestUrl"],
            payload["records"][0]["fields"]["manifestUrl"],
        )

    def test_dry_run_emits_artifact_records_for_selected_briefing(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            manifest_path = Path(tmp) / "pavbot-manifest.json"
            manifest_path.write_text(
                json.dumps(
                    {
                        "schemaVersion": 1,
                        "automations": [
                            {
                                "id": "pavbot-puls-dnia-news-3h",
                                "name": "Pavbot Puls Dnia 3h",
                                "kind": "automation",
                                "topic": "puls-dnia-news",
                                "topicPath": "research/puls-dnia-news",
                                "output": "research/puls-dnia-news/data/YYYY-MM-DD-HHMM-pulse-news.json",
                            }
                        ],
                        "topics": [
                            {"slug": "puls-dnia-news", "title": "Pavbot Puls Dnia News"},
                        ],
                        "artifacts": [
                            {
                                "id": "pulse-run",
                                "topic": "puls-dnia-news",
                                "type": "run",
                                "title": "Puls run",
                                "path": "research/puls-dnia-news/runs/2026-07-06-1800.md",
                                "url": "research/puls-dnia-news/runs/2026-07-06-1800.md",
                                "sizeBytes": 42,
                                "date": "2026-07-06",
                                "time": "18:00",
                            },
                            {
                                "id": "pulse-data",
                                "topic": "puls-dnia-news",
                                "type": "pulseNewsData",
                                "title": "Puls data",
                                "path": "research/puls-dnia-news/data/2026-07-06-1800-pulse-news.json",
                                "url": "research/puls-dnia-news/data/2026-07-06-1800-pulse-news.json",
                                "sizeBytes": 100,
                                "date": "2026-07-06",
                                "time": "18:00",
                            },
                        ],
                    }
                ),
                encoding="utf-8",
            )

            result = subprocess.run(
                [
                    sys.executable,
                    str(SCRIPT_PATH),
                    "dry-run",
                    "--manifest",
                    str(manifest_path),
                    "--topic",
                    "research/puls-dnia-news",
                ],
                cwd=REPO_ROOT,
                text=True,
                capture_output=True,
                check=False,
            )

        self.assertEqual(result.returncode, 0, result.stderr)
        payload = json.loads(result.stdout)
        briefing = payload["records"][0]
        artifacts = payload["artifacts"]

        self.assertEqual(briefing["fields"]["briefingId"], "pavbot-puls-dnia-news-3h:2026-07-06-1800")
        self.assertEqual(briefing["fields"]["artifactCount"], 2)
        self.assertEqual(
            json.loads(briefing["fields"]["artifactIdsJson"]),
            [
                "research/puls-dnia-news/data/2026-07-06-1800-pulse-news.json",
                "research/puls-dnia-news/runs/2026-07-06-1800.md",
            ],
        )
        self.assertEqual(
            briefing["fields"]["primaryArtifactId"],
            "research/puls-dnia-news/data/2026-07-06-1800-pulse-news.json",
        )
        self.assertEqual([artifact["recordType"] for artifact in artifacts], ["Artifact", "Artifact"])
        self.assertEqual(
            [artifact["fields"]["path"] for artifact in artifacts],
            [
                "research/puls-dnia-news/data/2026-07-06-1800-pulse-news.json",
                "research/puls-dnia-news/runs/2026-07-06-1800.md",
            ],
        )
        self.assertTrue(all(artifact["fields"]["briefingId"] == "pavbot-puls-dnia-news-3h:2026-07-06-1800" for artifact in artifacts))

    def test_dry_run_builds_reddit_radar_briefing_from_manifest_artifact(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            manifest_path = Path(tmp) / "pavbot-manifest.json"
            manifest_path.write_text(
                json.dumps(
                    {
                        "schemaVersion": 1,
                        "automations": [
                            {
                                "id": "pavbot-reddit-safari-humor-radar",
                                "name": "Pavbot Reddit Safari Humor Radar",
                                "kind": "automation",
                                "topic": "reddit-radar",
                                "topicPath": "research/reddit-radar",
                                "output": "research/reddit-radar/data/YYYY-MM-DD-HHMM-reddit-radar.json",
                            }
                        ],
                        "topics": [
                            {"slug": "reddit-radar", "title": "Pavbot Reddit Radar"},
                        ],
                        "artifacts": [
                            {
                                "id": "reddit-radar-data",
                                "topic": "reddit-radar",
                                "type": "redditRadarData",
                                "title": "Reddit Radar data",
                                "path": "research/reddit-radar/data/2026-07-07-0610-reddit-radar.json",
                                "url": "research/reddit-radar/data/2026-07-07-0610-reddit-radar.json",
                                "date": "2026-07-07",
                                "time": "06:10",
                            },
                        ],
                    }
                ),
                encoding="utf-8",
            )

            result = subprocess.run(
                [
                    sys.executable,
                    str(SCRIPT_PATH),
                    "dry-run",
                    "--manifest",
                    str(manifest_path),
                    "--topic",
                    "research/reddit-radar",
                ],
                cwd=REPO_ROOT,
                text=True,
                capture_output=True,
                check=False,
            )

        self.assertEqual(result.returncode, 0, result.stderr)
        payload = json.loads(result.stdout)
        self.assertEqual([record["fields"]["category"] for record in payload["records"]], ["reddit-radar"])
        self.assertEqual(payload["records"][0]["fields"]["briefingId"], "pavbot-reddit-safari-humor-radar:2026-07-07-0610")
        self.assertEqual(payload["records"][0]["notificationPayload"]["category"], "reddit-radar")


if __name__ == "__main__":
    unittest.main()
