from __future__ import annotations

import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


class PavbotCommitAndPushOutputsTest(unittest.TestCase):
    def setUp(self) -> None:
        self.repo_root = Path(__file__).resolve().parents[1]
        self.script_path = self.repo_root / "scripts" / "pavbot_commit_and_push_outputs.sh"

    def test_commits_and_pushes_only_topic_outputs_and_manifest(self) -> None:
        with self.temporary_repo() as repo:
            self.write_topic_artifact(repo, "tech-news", "runs/2026-06-23.md", "# Report\n")

            result = self.run_publish_script(repo, "research/tech-news")

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("pushed pavbot outputs", result.stdout)
            changed_files = self.git(
                repo,
                "diff-tree",
                "--no-commit-id",
                "--name-only",
                "-r",
                "HEAD",
                stdout=True,
            ).splitlines()
            self.assertEqual(
                sorted(changed_files),
                [
                    "public/pavbot-manifest.json",
                    "research/tech-news/runs/2026-06-23.md",
                ],
            )
            manifest = json.loads(
                self.git(repo, "show", "origin/main:public/pavbot-manifest.json", stdout=True)
            )
            self.assertIn(
                "research/tech-news/runs/2026-06-23.md",
                {artifact["path"] for artifact in manifest["artifacts"]},
            )
            local_head = self.git(repo, "rev-parse", "HEAD", stdout=True).strip()
            remote_head = self.git(repo, "ls-remote", "origin", "refs/heads/main", stdout=True).split()[0]
            self.assertEqual(local_head, remote_head)

    def test_llm_jobs_publish_includes_valid_data_json_outputs(self) -> None:
        with self.temporary_repo() as repo:
            self.write_topic_artifact(
                repo,
                "llm-ai-jobs-wroclaw",
                "runs/2026-06-25-0141.md",
                "# LLM/AI Jobs Wrocław\n\nDate: 2026-06-25 01:41 CEST\nStatus: Material update\n",
            )
            self.write_topic_artifact(
                repo,
                "llm-ai-jobs-wroclaw",
                "data/2026-06-25-0141-jobs.json",
                json.dumps(self.valid_jobs_data_payload(), ensure_ascii=False) + "\n",
            )

            result = self.run_publish_script(repo, "research/llm-ai-jobs-wroclaw")

            self.assertEqual(result.returncode, 0, result.stderr)
            changed_files = self.git(
                repo,
                "diff-tree",
                "--no-commit-id",
                "--name-only",
                "-r",
                "HEAD",
                stdout=True,
            ).splitlines()
            self.assertIn("research/llm-ai-jobs-wroclaw/data/2026-06-25-0141-jobs.json", changed_files)
            manifest = json.loads(
                self.git(repo, "show", "origin/main:public/pavbot-manifest.json", stdout=True)
            )
            by_path = {artifact["path"]: artifact for artifact in manifest["artifacts"]}
            self.assertEqual(
                by_path["research/llm-ai-jobs-wroclaw/data/2026-06-25-0141-jobs.json"]["type"],
                "jobsData",
            )

    def test_llm_jobs_publish_refuses_invalid_data_json(self) -> None:
        with self.temporary_repo() as repo:
            self.write_topic_artifact(
                repo,
                "llm-ai-jobs-wroclaw",
                "runs/2026-06-25-0141.md",
                "# LLM/AI Jobs Wrocław\n\nDate: 2026-06-25 01:41 CEST\nStatus: Material update\n",
            )
            self.write_topic_artifact(
                repo,
                "llm-ai-jobs-wroclaw",
                "data/2026-06-25-0141-jobs.json",
                json.dumps({"schemaVersion": 1, "runDate": "2026-06-25"}, ensure_ascii=False) + "\n",
            )

            result = self.run_publish_script(repo, "research/llm-ai-jobs-wroclaw")

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("invalid jobs data", result.stderr)
            self.assertIn("missing required field: status", result.stderr)
            self.assertEqual(
                self.git(repo, "rev-list", "--count", "HEAD", stdout=True).strip(),
                "1",
            )

    def test_research_publish_includes_valid_research_data_json_outputs(self) -> None:
        with self.temporary_repo() as repo:
            self.write_topic_artifact(
                repo,
                "tech-news",
                "runs/2026-06-25.md",
                "# Tech News\n\nDate: 2026-06-25\nStatus: Material update\n",
            )
            self.write_topic_artifact(
                repo,
                "tech-news",
                "data/2026-06-25-research.json",
                json.dumps(self.valid_research_data_payload(), ensure_ascii=False) + "\n",
            )

            result = self.run_publish_script(repo, "research/tech-news")

            self.assertEqual(result.returncode, 0, result.stderr)
            changed_files = self.git(
                repo,
                "diff-tree",
                "--no-commit-id",
                "--name-only",
                "-r",
                "HEAD",
                stdout=True,
            ).splitlines()
            self.assertIn("research/tech-news/data/2026-06-25-research.json", changed_files)
            manifest = json.loads(
                self.git(repo, "show", "origin/main:public/pavbot-manifest.json", stdout=True)
            )
            by_path = {artifact["path"]: artifact for artifact in manifest["artifacts"]}
            self.assertEqual(
                by_path["research/tech-news/data/2026-06-25-research.json"]["type"],
                "researchData",
            )

    def test_research_publish_refuses_invalid_research_data_json(self) -> None:
        with self.temporary_repo() as repo:
            self.write_topic_artifact(
                repo,
                "tech-news",
                "runs/2026-06-25.md",
                "# Tech News\n\nDate: 2026-06-25\nStatus: Material update\n",
            )
            self.write_topic_artifact(
                repo,
                "tech-news",
                "data/2026-06-25-research.json",
                json.dumps({"schemaVersion": 1, "topic": "tech-news"}, ensure_ascii=False) + "\n",
            )

            result = self.run_publish_script(repo, "research/tech-news")

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("invalid research data", result.stderr)
            self.assertIn("missing required field: articles", result.stderr)
            self.assertEqual(
                self.git(repo, "rev-list", "--count", "HEAD", stdout=True).strip(),
                "1",
            )

    def test_mobile_topic_isolated_publish_includes_valid_mobile_news_data(self) -> None:
        with self.temporary_repo() as repo:
            self.write_topic_artifact(
                repo,
                "aktualne-wydarzenia-mobile",
                "data/2026-06-25-1015-mobile-news.json",
                json.dumps(self.valid_mobile_news_data_payload(), ensure_ascii=False) + "\n",
            )
            self.write_topic_artifact(
                repo,
                "aktualne-wydarzenia-mobile",
                "pdfs/2026-06-25-1015-mobile-brief.pdf",
                "%PDF mobile brief",
            )
            self.write_topic_artifact(
                repo,
                "aktualne-wydarzenia-mobile",
                "podcasts/2026-06-25-1015/audio/female-piper/podcast.mp3",
                "female mp3",
            )
            self.write_topic_artifact(
                repo,
                "aktualne-wydarzenia-mobile",
                "podcasts/2026-06-25-1015/script.md",
                "# Podcast script\n\nTekst do lokalnego TTS.\n",
            )

            result = self.run_publish_script(repo, "research/aktualne-wydarzenia-mobile", isolated=True)

            self.assertEqual(result.returncode, 0, result.stderr)
            manifest = json.loads(
                self.git(repo, "show", "origin/main:public/pavbot-manifest.json", stdout=True)
            )
            by_path = {artifact["path"]: artifact for artifact in manifest["artifacts"]}
            self.assertEqual(
                by_path[
                    "research/aktualne-wydarzenia-mobile/data/2026-06-25-1015-mobile-news.json"
                ]["type"],
                "mobileNewsData",
            )
            self.assertEqual(
                by_path[
                    "research/aktualne-wydarzenia-mobile/podcasts/2026-06-25-1015/script.md"
                ]["type"],
                "podcastScript",
            )

    def test_mobile_topic_publish_refuses_invalid_mobile_news_data(self) -> None:
        with self.temporary_repo() as repo:
            payload = self.valid_mobile_news_data_payload()
            payload["sections"][0]["articles"][0]["ttsText"] = ""
            self.write_topic_artifact(
                repo,
                "aktualne-wydarzenia-mobile",
                "data/2026-06-25-1015-mobile-news.json",
                json.dumps(payload, ensure_ascii=False) + "\n",
            )
            self.write_topic_artifact(
                repo,
                "aktualne-wydarzenia-mobile",
                "pdfs/2026-06-25-1015-mobile-brief.pdf",
                "%PDF mobile brief",
            )

            result = self.run_publish_script(repo, "research/aktualne-wydarzenia-mobile", isolated=True)

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("invalid mobile news data", result.stderr)
            self.assertIn("article[0].ttsText is required", result.stderr)
            self.assertEqual(
                self.git(repo, "rev-list", "--count", "origin/main", stdout=True).strip(),
                "1",
            )

    def test_mobile_topic_publish_validates_latest_mobile_news_data_only(self) -> None:
        with self.temporary_repo() as repo:
            legacy_payload = self.valid_mobile_news_data_payload()
            legacy_payload["sections"] = legacy_payload["sections"][:1]
            legacy_payload["sections"][0]["articles"] = legacy_payload["sections"][0]["articles"][:1]
            self.write_topic_artifact(
                repo,
                "aktualne-wydarzenia-mobile",
                "data/2026-06-24-1015-mobile-news.json",
                json.dumps(legacy_payload, ensure_ascii=False) + "\n",
            )
            self.write_topic_artifact(
                repo,
                "aktualne-wydarzenia-mobile",
                "data/2026-06-25-1015-mobile-news.json",
                json.dumps(self.valid_mobile_news_data_payload(), ensure_ascii=False) + "\n",
            )
            self.write_topic_artifact(
                repo,
                "aktualne-wydarzenia-mobile",
                "pdfs/2026-06-25-1015-mobile-brief.pdf",
                "%PDF mobile brief",
            )

            result = self.run_publish_script(repo, "research/aktualne-wydarzenia-mobile", isolated=True)

            self.assertEqual(result.returncode, 0, result.stderr)
            manifest = json.loads(
                self.git(repo, "show", "origin/main:public/pavbot-manifest.json", stdout=True)
            )
            paths = {artifact["path"] for artifact in manifest["artifacts"]}
            self.assertIn(
                "research/aktualne-wydarzenia-mobile/data/2026-06-25-1015-mobile-news.json",
                paths,
            )

    def test_pulse_news_publish_includes_valid_pulse_news_data(self) -> None:
        with self.temporary_repo() as repo:
            self.write_topic_artifact(
                repo,
                "puls-dnia-news",
                "runs/2026-06-26-1200.md",
                "# Puls dnia\n\nDate: 2026-06-26 12:00 CEST\nStatus: Material update\n",
            )
            self.write_topic_artifact(
                repo,
                "puls-dnia-news",
                "data/2026-06-26-1200-pulse-news.json",
                json.dumps(self.valid_pulse_news_data_payload(), ensure_ascii=False) + "\n",
            )

            result = self.run_publish_script(repo, "research/puls-dnia-news", isolated=True)

            self.assertEqual(result.returncode, 0, result.stderr)
            changed_files = self.git(
                repo,
                "diff-tree",
                "--no-commit-id",
                "--name-only",
                "-r",
                "origin/main",
                stdout=True,
            ).splitlines()
            self.assertIn("research/puls-dnia-news/data/2026-06-26-1200-pulse-news.json", changed_files)
            manifest = json.loads(
                self.git(repo, "show", "origin/main:public/pavbot-manifest.json", stdout=True)
            )
            by_path = {artifact["path"]: artifact for artifact in manifest["artifacts"]}
            self.assertEqual(
                by_path["research/puls-dnia-news/data/2026-06-26-1200-pulse-news.json"]["type"],
                "pulseNewsData",
            )

    def test_pulse_news_isolated_publish_refreshes_stale_manifest_when_outputs_are_unchanged(self) -> None:
        with self.temporary_repo() as repo:
            self.write_topic_artifact(
                repo,
                "puls-dnia-news",
                "data/2026-06-26-1200-pulse-news.json",
                json.dumps(self.valid_pulse_news_data_payload(), ensure_ascii=False) + "\n",
            )
            self.write_existing_manifest(repo, "https://raw.githubusercontent.com/example/pavbot/main/")
            self.git(repo, "add", ".")
            self.git(repo, "commit", "-m", "seed pulse output with stale manifest")
            self.git(repo, "push", "origin", "main")
            head_before = self.git(repo, "rev-parse", "origin/main", stdout=True).strip()

            result = self.run_publish_script(repo, "research/puls-dnia-news", isolated=True)

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("pushed pavbot outputs", result.stdout)
            head_after = self.git(repo, "rev-parse", "origin/main", stdout=True).strip()
            self.assertNotEqual(head_before, head_after)
            changed_files = self.git(
                repo,
                "diff-tree",
                "--no-commit-id",
                "--name-only",
                "-r",
                "origin/main",
                stdout=True,
            ).splitlines()
            self.assertEqual(changed_files, ["public/pavbot-manifest.json"])
            manifest = json.loads(
                self.git(repo, "show", "origin/main:public/pavbot-manifest.json", stdout=True)
            )
            by_path = {artifact["path"]: artifact for artifact in manifest["artifacts"]}
            self.assertEqual(
                by_path["research/puls-dnia-news/data/2026-06-26-1200-pulse-news.json"]["type"],
                "pulseNewsData",
            )

    def test_pulse_news_publish_refuses_invalid_pulse_news_data(self) -> None:
        with self.temporary_repo() as repo:
            payload = self.valid_pulse_news_data_payload()
            payload["items"] = payload["items"][:11]
            self.write_topic_artifact(
                repo,
                "puls-dnia-news",
                "data/2026-06-26-1200-pulse-news.json",
                json.dumps(payload, ensure_ascii=False) + "\n",
            )

            result = self.run_publish_script(repo, "research/puls-dnia-news", isolated=True)

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("invalid pulse news data", result.stderr)
            self.assertIn("items must contain at least 12 items", result.stderr)
            self.assertEqual(
                self.git(repo, "rev-list", "--count", "origin/main", stdout=True).strip(),
                "1",
            )

    def test_mobile_topic_isolated_publish_anchors_latest_package_on_mobile_news_data(self) -> None:
        with self.temporary_repo() as repo:
            self.write_topic_artifact(
                repo,
                "aktualne-wydarzenia-mobile",
                "data/2026-06-25-1015-mobile-news.json",
                json.dumps(self.valid_mobile_news_data_payload(), ensure_ascii=False) + "\n",
            )
            self.write_topic_artifact(
                repo,
                "aktualne-wydarzenia-mobile",
                "podcasts/2026-06-25-1015/script.md",
                "# Complete script\n",
            )
            self.write_topic_artifact(
                repo,
                "aktualne-wydarzenia-mobile",
                "podcasts/2026-06-26-1015/script.md",
                "# Orphan script without mobileNewsData\n",
            )

            result = self.run_publish_script(repo, "research/aktualne-wydarzenia-mobile", isolated=True)

            self.assertEqual(result.returncode, 0, result.stderr)
            manifest = json.loads(
                self.git(repo, "show", "origin/main:public/pavbot-manifest.json", stdout=True)
            )
            paths = {artifact["path"] for artifact in manifest["artifacts"]}

            self.assertIn(
                "research/aktualne-wydarzenia-mobile/data/2026-06-25-1015-mobile-news.json",
                paths,
            )
            self.assertIn(
                "research/aktualne-wydarzenia-mobile/podcasts/2026-06-25-1015/script.md",
                paths,
            )
            self.assertNotIn(
                "research/aktualne-wydarzenia-mobile/podcasts/2026-06-26-1015/script.md",
                paths,
            )

    def test_isolated_publish_uses_current_manifest_generator_for_jobs_data(self) -> None:
        with self.temporary_repo() as repo:
            stale_generator = repo / "scripts" / "generate_pavbot_manifest.py"
            stale_generator.write_text(
                """#!/usr/bin/env python3
import json
from pathlib import Path
Path("public").mkdir(exist_ok=True)
Path("public/pavbot-manifest.json").write_text(json.dumps({
    "schemaVersion": 1,
    "title": "stale",
    "generatedAt": "2026-06-22T00:00:00+00:00",
    "rawBaseUrl": "",
    "automations": [],
    "topics": [],
    "artifacts": []
}) + "\\n", encoding="utf-8")
""",
                encoding="utf-8",
            )
            self.git(repo, "add", "scripts/generate_pavbot_manifest.py")
            self.git(repo, "commit", "-m", "stale manifest generator")
            self.git(repo, "push", "origin", "main")
            self.write_topic_artifact(
                repo,
                "llm-ai-jobs-wroclaw",
                "runs/2026-06-25-0141.md",
                "# LLM/AI Jobs Wrocław\n\nDate: 2026-06-25 01:41 CEST\nStatus: Material update\n",
            )
            self.write_topic_artifact(
                repo,
                "llm-ai-jobs-wroclaw",
                "data/2026-06-25-0141-jobs.json",
                json.dumps(self.valid_jobs_data_payload(), ensure_ascii=False) + "\n",
            )

            result = self.run_publish_script(repo, "research/llm-ai-jobs-wroclaw", isolated=True)

            self.assertEqual(result.returncode, 0, result.stderr)
            manifest = json.loads(
                self.git(repo, "show", "origin/main:public/pavbot-manifest.json", stdout=True)
            )
            by_path = {artifact["path"]: artifact for artifact in manifest["artifacts"]}
            self.assertEqual(
                by_path["research/llm-ai-jobs-wroclaw/data/2026-06-25-0141-jobs.json"]["type"],
                "jobsData",
            )

    def test_exits_without_commit_when_outputs_are_unchanged(self) -> None:
        with self.temporary_repo() as repo:
            self.write_topic_artifact(repo, "tech-news", "runs/2026-06-23.md", "# Report\n")
            first = self.run_publish_script(repo, "research/tech-news")
            self.assertEqual(first.returncode, 0, first.stderr)
            head_after_first_publish = self.git(repo, "rev-parse", "HEAD", stdout=True).strip()

            second = self.run_publish_script(repo, "research/tech-news")

            self.assertEqual(second.returncode, 0, second.stderr)
            self.assertIn("no publishable changes", second.stdout)
            self.assertEqual(
                self.git(repo, "rev-parse", "HEAD", stdout=True).strip(),
                head_after_first_publish,
            )

    def test_uses_existing_manifest_raw_base_url_when_manifest_env_is_missing(self) -> None:
        with self.temporary_repo() as repo:
            self.write_existing_manifest(repo, "https://raw.githubusercontent.com/example/from-manifest/main/")
            self.write_topic_artifact(repo, "tech-news", "runs/2026-06-23.md", "# Report\n")

            result = self.run_publish_script(repo, "research/tech-news", manifest_url=None)

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn(
                "using Pavbot manifest URL: https://raw.githubusercontent.com/example/from-manifest/main/public/pavbot-manifest.json",
                result.stdout,
            )
            manifest = json.loads((repo / "public" / "pavbot-manifest.json").read_text(encoding="utf-8"))
            self.assertEqual(
                manifest["rawBaseUrl"],
                "https://raw.githubusercontent.com/example/from-manifest/main/",
            )

    def test_derives_manifest_url_from_https_github_origin_when_env_is_missing(self) -> None:
        with self.temporary_repo() as repo:
            self.configure_github_origin_rewrite(repo, "https://github.com/example/pavbot.git")
            self.write_topic_artifact(repo, "tech-news", "runs/2026-06-23.md", "# Report\n")

            result = self.run_publish_script(repo, "research/tech-news", manifest_url=None)

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn(
                "using Pavbot manifest URL: https://raw.githubusercontent.com/example/pavbot/main/public/pavbot-manifest.json",
                result.stdout,
            )
            manifest = json.loads((repo / "public" / "pavbot-manifest.json").read_text(encoding="utf-8"))
            self.assertEqual(
                manifest["rawBaseUrl"],
                "https://raw.githubusercontent.com/example/pavbot/main/",
            )

    def test_derives_manifest_url_from_ssh_github_origin_when_env_is_missing(self) -> None:
        with self.temporary_repo() as repo:
            self.configure_github_origin_rewrite(repo, "git@github.com:example/pavbot.git")
            self.write_topic_artifact(repo, "tech-news", "runs/2026-06-23.md", "# Report\n")

            result = self.run_publish_script(repo, "research/tech-news", manifest_url=None)

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn(
                "using Pavbot manifest URL: https://raw.githubusercontent.com/example/pavbot/main/public/pavbot-manifest.json",
                result.stdout,
            )
            manifest = json.loads((repo / "public" / "pavbot-manifest.json").read_text(encoding="utf-8"))
            self.assertEqual(
                manifest["rawBaseUrl"],
                "https://raw.githubusercontent.com/example/pavbot/main/",
            )

    def test_derives_manifest_url_from_additional_supported_github_origin_formats(self) -> None:
        remote_urls = [
            "https://github.com/example/pavbot",
            "ssh://git@github.com/example/pavbot.git",
        ]
        for remote_url in remote_urls:
            with self.subTest(remote_url=remote_url), self.temporary_repo() as repo:
                self.configure_github_origin_rewrite(repo, remote_url)
                self.write_topic_artifact(repo, "tech-news", "runs/2026-06-23.md", "# Report\n")

                result = self.run_publish_script(repo, "research/tech-news", manifest_url=None)

                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn(
                    "using Pavbot manifest URL: https://raw.githubusercontent.com/example/pavbot/main/public/pavbot-manifest.json",
                    result.stdout,
                )
                manifest = json.loads((repo / "public" / "pavbot-manifest.json").read_text(encoding="utf-8"))
                self.assertEqual(
                    manifest["rawBaseUrl"],
                    "https://raw.githubusercontent.com/example/pavbot/main/",
                )

    def test_explicit_manifest_url_still_takes_precedence(self) -> None:
        with self.temporary_repo() as repo:
            self.write_existing_manifest(repo, "https://raw.githubusercontent.com/example/from-manifest/main/")
            self.write_topic_artifact(repo, "tech-news", "runs/2026-06-23.md", "# Report\n")

            result = self.run_publish_script(
                repo,
                "research/tech-news",
                manifest_url="https://raw.githubusercontent.com/example/override/main/public/pavbot-manifest.json",
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn(
                "using Pavbot manifest URL: https://raw.githubusercontent.com/example/override/main/public/pavbot-manifest.json",
                result.stdout,
            )
            manifest = json.loads((repo / "public" / "pavbot-manifest.json").read_text(encoding="utf-8"))
            self.assertEqual(
                manifest["rawBaseUrl"],
                "https://raw.githubusercontent.com/example/override/main/",
            )

    def test_refuses_to_publish_when_changes_exist_outside_allowlist(self) -> None:
        with self.temporary_repo() as repo:
            self.write_topic_artifact(repo, "tech-news", "runs/2026-06-23.md", "# Report\n")
            (repo / "docs" / "unrelated.md").write_text("do not publish\n", encoding="utf-8")

            result = self.run_publish_script(repo, "research/tech-news")

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("outside allowed publish paths", result.stderr)
            self.assertEqual(
                self.git(repo, "rev-list", "--count", "HEAD", stdout=True).strip(),
                "1",
            )

    def test_refuses_in_place_publish_when_topic_tool_changes_exist(self) -> None:
        with self.temporary_repo() as repo:
            self.write_topic_artifact(repo, "tech-news", "runs/2026-06-23.md", "# Report\n")
            tool_path = repo / "research" / "tech-news" / "tools" / "helper.sh"
            tool_path.parent.mkdir(parents=True, exist_ok=True)
            tool_path.write_text("#!/usr/bin/env bash\n", encoding="utf-8")

            result = self.run_publish_script(repo, "research/tech-news")

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("outside allowed publish paths", result.stderr)
            self.assertIn("research/tech-news/tools/helper.sh", result.stderr)

    def test_isolated_publish_ignores_development_changes_and_pushes_outputs(self) -> None:
        with self.temporary_repo() as repo:
            self.write_topic_artifact(repo, "tech-news", "runs/2026-06-23.md", "# Report\n")
            (repo / "docs" / "unrelated.md").write_text("development change\n", encoding="utf-8")
            tool_path = repo / "research" / "tech-news" / "tools" / "helper.sh"
            tool_path.parent.mkdir(parents=True, exist_ok=True)
            tool_path.write_text("#!/usr/bin/env bash\n", encoding="utf-8")

            result = self.run_publish_script(repo, "research/tech-news", isolated=True)

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("pushed pavbot outputs", result.stdout)
            changed_files = self.git(
                repo,
                "diff-tree",
                "--no-commit-id",
                "--name-only",
                "-r",
                "origin/main",
                stdout=True,
            ).splitlines()
            self.assertEqual(
                sorted(changed_files),
                [
                    "public/pavbot-manifest.json",
                    "research/tech-news/runs/2026-06-23.md",
                ],
            )
            self.assertFalse((repo / "public" / "pavbot-manifest.json").exists())
            self.assertTrue((repo / "docs" / "unrelated.md").exists())
            self.assertTrue(tool_path.exists())

    def test_isolated_publish_reports_noop_without_push_message(self) -> None:
        with self.temporary_repo() as repo:
            self.write_topic_artifact(repo, "tech-news", "runs/2026-06-23.md", "# Report\n")
            first = self.run_publish_script(repo, "research/tech-news", isolated=True)
            self.assertEqual(first.returncode, 0, first.stderr)

            second = self.run_publish_script(repo, "research/tech-news", isolated=True)

            self.assertEqual(second.returncode, 0, second.stderr)
            self.assertIn("no publishable changes", second.stdout)
            self.assertNotIn("pushed pavbot outputs", second.stdout)

    def test_mobile_topic_refuses_in_place_publish_for_editorial_artifacts(self) -> None:
        with self.temporary_repo() as repo:
            self.write_topic_artifact(
                repo,
                "aktualne-wydarzenia-mobile",
                "topic.md",
                "# Topic Contract: aktualne-wydarzenia-mobile\n",
            )
            self.write_topic_artifact(
                repo,
                "aktualne-wydarzenia-mobile",
                "runs/2026-06-24-1015.md",
                "# Report\n",
            )
            self.write_topic_artifact(
                repo,
                "aktualne-wydarzenia-mobile",
                "podcasts/2026-06-24-1015/script.md",
                "# Script\n",
            )

            result = self.run_publish_script(repo, "research/aktualne-wydarzenia-mobile")

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("outside allowed publish paths", result.stderr)
            self.assertIn(
                "research/aktualne-wydarzenia-mobile/runs/2026-06-24-1015.md",
                result.stderr,
            )

    def test_mobile_topic_isolated_publish_pushes_only_public_pdf_and_audio_and_removes_old_public_files(self) -> None:
        with self.temporary_repo() as repo:
            self.write_topic_artifact(
                repo,
                "aktualne-wydarzenia-mobile",
                "topic.md",
                "# Topic Contract: aktualne-wydarzenia-mobile\n",
            )
            self.write_topic_artifact(
                repo,
                "aktualne-wydarzenia-mobile",
                "runs/2026-06-23-1015.md",
                "# Report\n",
            )
            self.write_topic_artifact(
                repo,
                "aktualne-wydarzenia-mobile",
                "index.md",
                "# Index\n",
            )
            self.write_topic_artifact(
                repo,
                "aktualne-wydarzenia-mobile",
                "backlog.md",
                "# Backlog\n",
            )
            self.write_topic_artifact(
                repo,
                "aktualne-wydarzenia-mobile",
                "pdfs/2026-06-23-1015-newspaper.pdf",
                "%PDF old newspaper",
            )
            self.write_topic_artifact(
                repo,
                "aktualne-wydarzenia-mobile",
                "podcasts/2026-06-23-1015/script.md",
                "# Script\n",
            )
            self.write_topic_artifact(
                repo,
                "aktualne-wydarzenia-mobile",
                "podcasts/2026-06-23-1015/sources.md",
                "# Sources\n",
            )
            self.write_topic_artifact(
                repo,
                "aktualne-wydarzenia-mobile",
                "podcasts/2026-06-23-1015/tts_variants.json",
                "{\"language\": \"pl\"}\n",
            )
            self.write_topic_artifact(
                repo,
                "aktualne-wydarzenia-mobile",
                "podcasts/2026-06-23-1015/audio/female-piper/render.json",
                "{\"status\": \"ok\"}\n",
            )
            self.git(repo, "add", ".")
            self.git(repo, "commit", "-m", "seed mobile topic")
            self.git(repo, "push", "origin", "main")

            self.write_topic_artifact(
                repo,
                "aktualne-wydarzenia-mobile",
                "data/2026-06-24-1015-mobile-news.json",
                json.dumps(self.valid_mobile_news_data_payload(), ensure_ascii=False) + "\n",
            )
            self.write_topic_artifact(
                repo,
                "aktualne-wydarzenia-mobile",
                "pdfs/2026-06-24-1015-mobile-brief.pdf",
                "%PDF mobile brief",
            )
            self.write_topic_artifact(
                repo,
                "aktualne-wydarzenia-mobile",
                "podcasts/2026-06-24-1015/audio/female-piper/podcast.mp3",
                "female mp3",
            )
            self.write_topic_artifact(
                repo,
                "aktualne-wydarzenia-mobile",
                "podcasts/2026-06-24-1015/audio/male-xtts/podcast.mp3",
                "male mp3",
            )
            self.write_topic_artifact(
                repo,
                "aktualne-wydarzenia-mobile",
                "podcasts/2026-06-24-1015/script.md",
                "# Local script\n",
            )

            result = self.run_publish_script(repo, "research/aktualne-wydarzenia-mobile", isolated=True)

            self.assertEqual(result.returncode, 0, result.stderr)
            changed_files = self.git(
                repo,
                "diff-tree",
                "--no-commit-id",
                "--name-only",
                "-r",
                "origin/main",
                stdout=True,
            ).splitlines()
            self.assertEqual(
                sorted(changed_files),
                [
                    "public/pavbot-manifest.json",
                    "research/aktualne-wydarzenia-mobile/backlog.md",
                    "research/aktualne-wydarzenia-mobile/data/2026-06-24-1015-mobile-news.json",
                    "research/aktualne-wydarzenia-mobile/index.md",
                    "research/aktualne-wydarzenia-mobile/pdfs/2026-06-23-1015-newspaper.pdf",
                    "research/aktualne-wydarzenia-mobile/pdfs/2026-06-24-1015-mobile-brief.pdf",
                    "research/aktualne-wydarzenia-mobile/podcasts/2026-06-23-1015/audio/female-piper/render.json",
                    "research/aktualne-wydarzenia-mobile/podcasts/2026-06-23-1015/script.md",
                    "research/aktualne-wydarzenia-mobile/podcasts/2026-06-23-1015/sources.md",
                    "research/aktualne-wydarzenia-mobile/podcasts/2026-06-23-1015/tts_variants.json",
                    "research/aktualne-wydarzenia-mobile/podcasts/2026-06-24-1015/audio/female-piper/podcast.mp3",
                    "research/aktualne-wydarzenia-mobile/podcasts/2026-06-24-1015/audio/male-xtts/podcast.mp3",
                    "research/aktualne-wydarzenia-mobile/podcasts/2026-06-24-1015/script.md",
                    "research/aktualne-wydarzenia-mobile/runs/2026-06-23-1015.md",
                ],
            )

            manifest = json.loads(
                self.git(repo, "show", "origin/main:public/pavbot-manifest.json", stdout=True)
            )
            mobile_artifacts = [
                artifact["path"]
                for artifact in manifest["artifacts"]
                if artifact["topic"] == "aktualne-wydarzenia-mobile"
            ]
            self.assertEqual(
                sorted(mobile_artifacts),
                [
                    "research/aktualne-wydarzenia-mobile/data/2026-06-24-1015-mobile-news.json",
                    "research/aktualne-wydarzenia-mobile/pdfs/2026-06-24-1015-mobile-brief.pdf",
                    "research/aktualne-wydarzenia-mobile/podcasts/2026-06-24-1015/audio/female-piper/podcast.mp3",
                    "research/aktualne-wydarzenia-mobile/podcasts/2026-06-24-1015/audio/male-xtts/podcast.mp3",
                    "research/aktualne-wydarzenia-mobile/podcasts/2026-06-24-1015/script.md",
                ],
            )

    def temporary_repo(self):
        return TemporaryPavbotRepo(self.repo_root, self.script_path)

    def run_publish_script(
        self,
        repo: Path,
        topic_path: str,
        isolated: bool = False,
        manifest_url: str | None = "https://raw.githubusercontent.com/example/pavbot/main/public/pavbot-manifest.json",
    ) -> subprocess.CompletedProcess[str]:
        self.assertTrue(self.script_path.exists(), f"missing script: {self.script_path}")
        env = os.environ.copy()
        env.pop("PAVBOT_RAW_BASE_URL", None)
        if manifest_url is None:
            env.pop("PAVBOT_MANIFEST_URL", None)
        else:
            env["PAVBOT_MANIFEST_URL"] = manifest_url
        args = ["bash", str(self.script_path)]
        if isolated:
            args.append("--isolated")
        args.append(topic_path)
        return subprocess.run(
            args,
            cwd=repo,
            capture_output=True,
            env=env,
            text=True,
            check=False,
        )

    def write_topic_artifact(self, repo: Path, topic: str, relative_path: str, content: str) -> None:
        topic_root = repo / "research" / topic
        topic_root.mkdir(parents=True, exist_ok=True)
        topic_file = topic_root / "topic.md"
        if not topic_file.exists():
            topic_file.write_text(f"# Topic Contract: {topic}\n", encoding="utf-8")
        path = repo / "research" / topic / relative_path
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8")

    def write_existing_manifest(self, repo: Path, raw_base_url: str) -> None:
        manifest_path = repo / "public" / "pavbot-manifest.json"
        manifest_path.parent.mkdir(parents=True, exist_ok=True)
        manifest_path.write_text(
            json.dumps(
                {
                    "schemaVersion": 1,
                    "title": "Pavbot Automation Manifest",
                    "generatedAt": "2026-06-22T00:00:00+00:00",
                    "rawBaseUrl": raw_base_url,
                    "automations": [],
                    "topics": [],
                    "artifacts": [],
                },
                indent=2,
            )
            + "\n",
            encoding="utf-8",
        )

    def valid_jobs_data_payload(self) -> dict:
        return {
            "schemaVersion": 1,
            "status": "Material update",
            "runDate": "2026-06-25",
            "runTime": "01:41",
            "executiveSummary": "Runda przyniosła nowe role LLM/AI.",
            "opportunities": [
                {
                    "rank": 1,
                    "title": "Principal AI Engineer",
                    "company": "CKSource",
                    "location": "Remote Poland",
                    "workMode": "Remote",
                    "compensation": "38 000-45 000 PLN",
                    "seniority": "Principal",
                    "fitSummary": "Agentic workflows i AI-assisted engineering.",
                    "whyInteresting": "Silny praktyczny fit do systemów LLM.",
                    "uncertainty": "Tytuł różni się między hubem i kartą.",
                    "sourceURLs": ["https://example.com/job"],
                    "tags": ["LLM", "Agentic AI"],
                }
            ],
            "changes": ["Nowa oficjalna rola"],
            "risks": ["Drift tytułu"],
            "recommendedActions": ["Sprawdzić status w kolejnej rundzie"],
            "checkedSources": [{"title": "CKSource careers", "url": "https://example.com"}],
        }

    def valid_research_data_payload(self) -> dict:
        return {
            "schemaVersion": 1,
            "topic": "tech-news",
            "runDate": "2026-06-25",
            "runTime": None,
            "status": "Material update",
            "leadParagraphs": ["AI i infrastruktura są dziś kluczowe."],
            "summaryBullets": ["AI: OpenAI publikuje zmianę."],
            "articles": [
                {
                    "id": "tech-1",
                    "section": "AI",
                    "title": "OpenAI publikuje zmianę",
                    "standfirst": "OpenAI publikuje zmianę.",
                    "whatHappened": "OpenAI publikuje zmianę.",
                    "whyItMatters": "To ważne dla adopcji AI.",
                    "deeperAnalysis": ["Analiza pierwsza.", "Analiza druga."],
                    "contextPoints": ["Co się stało: test.", "Dlaczego ważne: test."],
                    "sources": [{"title": "OpenAI", "url": "https://openai.com/news"}],
                    "priority": "High",
                    "tags": ["AI"],
                }
            ],
            "podcastTopics": [],
            "checkedSources": [{"title": "OpenAI", "url": "https://openai.com/news"}],
        }

    def valid_mobile_news_data_payload(self) -> dict:
        sections = []
        for section in ["Ogólne", "Polska", "Polityka", "Sprawy zagraniczne", "Technologia"]:
            slug = {
                "Ogólne": "ogolne",
                "Polska": "polska",
                "Polityka": "polityka",
                "Sprawy zagraniczne": "sprawy-zagraniczne",
                "Technologia": "technologia",
            }[section]
            sections.append(
                {
                    "id": slug,
                    "title": section,
                    "summary": f"{section}: syntetyczny opis stanu informacji bez kopiowania leadu artykułu.",
                    "articles": [
                        self.mobile_news_article_payload(slug, section, 1),
                        self.mobile_news_article_payload(slug, section, 2),
                    ],
                }
            )
        return {
            "schemaVersion": 1,
            "topic": "aktualne-wydarzenia-mobile",
            "runDate": "2026-06-25",
            "runTime": "10:15",
            "status": "Material update",
            "headline": "Wydanie dnia",
            "leadParagraphs": ["Najważniejszy opis dnia."],
            "sections": sections,
            "checkedSources": [{"title": "KPRM", "url": "https://www.gov.pl/web/premier"}],
            "audioArtifacts": [],
        }

    def mobile_news_article_payload(self, slug: str, section: str, index: int) -> dict:
        return {
            "id": f"{slug}-{index}",
            "section": section,
            "title": f"{section}: temat {index}",
            "lead": f"{section} ma osobny lead artykułu numer {index}.",
            "facts": [f"Potwierdzony fakt {index} dla sekcji {section}."],
            "analysis": f"Analiza numer {index} porządkuje znaczenie tematu w sekcji {section}.",
            "whyItMatters": "Użytkownik dostaje jasny sens wydarzenia.",
            "sources": [{"title": "KPRM", "url": f"https://www.gov.pl/web/premier?test={slug}-{index}"}],
            "tags": [section],
            "ttsText": f"{section}: temat {index}. {section} ma osobny lead artykułu numer {index}.",
            "priority": "High" if index == 1 else "Medium",
        }

    def valid_pulse_news_data_payload(self) -> dict:
        sections = [
            "Polska",
            "Świat",
            "Polityka",
            "Bezpieczeństwo",
            "Gospodarka",
            "Technologia",
            "Alerty",
            "Polska",
            "Świat",
            "Gospodarka",
            "Technologia",
            "Bezpieczeństwo",
        ]
        items = []
        for index, section in enumerate(sections, start=1):
            items.append(
                {
                    "id": f"pulse-{index}",
                    "section": section,
                    "title": f"Temat dnia {index}",
                    "lead": f"Krótki opis tematu {index} z ostatnich godzin.",
                    "whatHappened": f"Co się stało w temacie {index}.",
                    "keyFacts": [f"Potwierdzony fakt {index}.", f"Drugi fakt {index}."],
                    "reactions": [f"Reakcja instytucji {index}."],
                    "whyItMatters": f"Dlaczego temat {index} jest ważny dla użytkownika.",
                    "context": f"Kontekst tematu {index} i jego wpływ na kolejne godziny.",
                    "watchNext": [f"Sprawdź kolejne komunikaty w sprawie {index}."],
                    "sources": [
                        {
                            "title": "TVN24" if index % 3 == 0 else "BBC",
                            "url": f"https://example.com/source-{index}",
                        }
                    ],
                    "tags": [section, "Puls dnia"],
                    "priority": "High" if index <= 4 else "Medium",
                }
            )
        return {
            "schemaVersion": 1,
            "topic": "puls-dnia-news",
            "runDate": "2026-06-26",
            "runTime": "12:00",
            "status": "Material update",
            "headline": "Puls dnia",
            "summary": "Najważniejsze tematy z ostatnich trzech godzin.",
            "items": items,
            "checkedSources": [
                {"title": "TVN24", "url": "https://www.tvn24.pl"},
                {"title": "BBC", "url": "https://www.bbc.com/news"},
                {"title": "CNN", "url": "https://www.cnn.com"},
            ],
        }

    def configure_github_origin_rewrite(self, repo: Path, remote_url: str) -> None:
        local_origin = self.git(repo, "remote", "get-url", "origin", stdout=True).strip()
        self.git(repo, "remote", "set-url", "origin", remote_url)
        self.git(repo, "config", f"url.{local_origin}.insteadOf", remote_url)

    def git(self, repo: Path, *args: str, stdout: bool = False) -> str:
        result = subprocess.run(
            ["git", *args],
            cwd=repo,
            capture_output=True,
            text=True,
            check=True,
        )
        return result.stdout if stdout else ""


class TemporaryPavbotRepo:
    def __init__(self, source_repo: Path, publish_script: Path) -> None:
        self.source_repo = source_repo
        self.publish_script = publish_script
        self.tempdir: tempfile.TemporaryDirectory[str] | None = None
        self.repo: Path | None = None

    def __enter__(self) -> Path:
        self.tempdir = tempfile.TemporaryDirectory()
        root = Path(self.tempdir.name)
        origin = root / "origin.git"
        repo = root / "work"
        subprocess.run(["git", "init", "--bare", "--initial-branch=main", str(origin)], check=True)
        subprocess.run(["git", "init", "--initial-branch=main", str(repo)], check=True)
        self.repo = repo
        self.git("config", "user.email", "pavbot@example.test")
        self.git("config", "user.name", "Pavbot Test")
        self.git("remote", "add", "origin", str(origin))
        self.create_minimal_workspace(repo)
        self.git("add", ".")
        self.git("commit", "-m", "initial workspace")
        self.git("push", "-u", "origin", "main")
        return repo

    def __exit__(self, exc_type, exc, tb) -> None:
        assert self.tempdir is not None
        self.tempdir.cleanup()

    def create_minimal_workspace(self, repo: Path) -> None:
        (repo / "scripts").mkdir(parents=True)
        shutil.copy2(self.source_repo / "scripts" / "generate_pavbot_manifest.py", repo / "scripts")
        shutil.copy2(self.source_repo / "scripts" / "validate_jobs_data.py", repo / "scripts")
        shutil.copy2(self.source_repo / "scripts" / "validate_research_data.py", repo / "scripts")
        shutil.copy2(self.source_repo / "scripts" / "validate_mobile_news_data.py", repo / "scripts")
        shutil.copy2(self.source_repo / "scripts" / "validate_pulse_news_data.py", repo / "scripts")
        (repo / "docs").mkdir()
        (repo / "docs" / "how-to-use.md").write_text(
            "\n".join(
                [
                    "# How To Use Pavbot",
                    "",
                    "The current active automations are:",
                    "",
                    "- Name: `Pavbot Tech Research 08:00`",
                    "- ID: `pavbot-tech-research`",
                    "- Topic: `research/tech-news`",
                    "- Cadence: daily at 08:00 local time",
                    "",
                ]
            ),
            encoding="utf-8",
        )
        for slug in ("tech-news", "llm-ai-jobs-wroclaw", "aktualne-wydarzenia-mobile", "puls-dnia-news"):
            topic = repo / "research" / slug
            topic.mkdir(parents=True)
            (topic / "topic.md").write_text(f"# Topic Contract: {slug}\n", encoding="utf-8")
            (topic / "index.md").write_text("# Index\n", encoding="utf-8")
            (topic / "backlog.md").write_text("# Backlog\n", encoding="utf-8")

    def git(self, *args: str) -> None:
        assert self.repo is not None
        subprocess.run(["git", *args], cwd=self.repo, check=True, capture_output=True, text=True)


if __name__ == "__main__":
    unittest.main()
