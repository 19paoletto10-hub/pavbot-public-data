from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
SCRIPT_PATH = REPO_ROOT / "scripts" / "publish_cloudkit_briefings.py"


class PublishCloudKitBriefingsTest(unittest.TestCase):
    def test_build_notification_payload_matches_ios_apns_contract(self) -> None:
        sys.path.insert(0, str(REPO_ROOT / "scripts"))
        try:
            import publish_cloudkit_briefings
        finally:
            sys.path.pop(0)

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
