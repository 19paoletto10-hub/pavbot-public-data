from __future__ import annotations

import argparse
import importlib
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


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
                "briefingId": "puls-dnia-news:2026-07-06-1800",
                "category": "puls-dnia-news",
                "title": "Pavbot Puls Dnia News · 2026-07-06 18:00",
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
                        "subtitle": "Pavbot Puls Dnia News · 2026-07-06 18:00",
                        "body": "Nowe dane: Pavbot Puls Dnia News · 2026-07-06 18:00",
                    },
                    "sound": "default",
                },
                "briefingId": "puls-dnia-news:2026-07-06-1800",
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

        self.assertEqual([call[2] for call in calls], ["delete-records", "create-record"])
        self.assertIn("--record-type", calls[1])
        self.assertIn("--fields-json", calls[1])
        created_fields = json.loads(calls[1][calls[1].index("--fields-json") + 1])
        self.assertEqual(created_fields["briefingId"]["value"], "puls-dnia-news:2026-07-06-1800")
        self.assertEqual(created_fields["category"]["value"], "puls-dnia-news")
        self.assertEqual(created_fields["status"]["value"], "ready")

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
        self.assertEqual(payload["records"][0]["notificationPayload"]["briefingId"], "puls-dnia-news:2026-07-06-1800")
        self.assertEqual(payload["records"][0]["notificationPayload"]["category"], "puls-dnia-news")
        self.assertEqual(
            payload["records"][0]["notificationPayload"]["manifestUrl"],
            payload["records"][0]["fields"]["manifestUrl"],
        )

    def test_dry_run_builds_reddit_radar_briefing_from_manifest_artifact(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            manifest_path = Path(tmp) / "pavbot-manifest.json"
            manifest_path.write_text(
                json.dumps(
                    {
                        "schemaVersion": 1,
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
        self.assertEqual(payload["records"][0]["fields"]["briefingId"], "reddit-radar:2026-07-07-0610")
        self.assertEqual(payload["records"][0]["notificationPayload"]["category"], "reddit-radar")


if __name__ == "__main__":
    unittest.main()
