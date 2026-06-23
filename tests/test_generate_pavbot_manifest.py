from __future__ import annotations

import importlib.util
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch


def load_generator():
    module_path = (
        Path(__file__).resolve().parents[1]
        / "scripts"
        / "generate_pavbot_manifest.py"
    )
    spec = importlib.util.spec_from_file_location("generate_pavbot_manifest", module_path)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


class GeneratePavbotManifestTest(unittest.TestCase):
    def setUp(self) -> None:
        self.repo_root = Path(__file__).resolve().parents[1]
        self.raw_base_url = "https://raw.githubusercontent.com/example/pavbot/main/"

    def test_manifest_includes_active_automations_from_docs(self) -> None:
        generator = load_generator()

        manifest = generator.build_manifest(
            self.repo_root,
            raw_base_url=self.raw_base_url,
        )

        automation_ids = {item["id"] for item in manifest["automations"]}
        self.assertIn("codex-agent-automation-daily-research", automation_ids)
        self.assertIn("pavbot-tech-podcast-09-00", automation_ids)
        self.assertIn("pavbot-polska-wiat-research-08-30", automation_ids)
        self.assertIn("pavbot-polska-wiat-podcast-09-30", automation_ids)
        self.assertIn("pavbot-llm-ai-jobs-wroclaw-research", automation_ids)
        self.assertTrue(all(item["enabled"] for item in manifest["automations"]))

        tech_research = next(
            item
            for item in manifest["automations"]
            if item["id"] == "codex-agent-automation-daily-research"
        )
        self.assertEqual(tech_research["topic"], "tech-news")
        self.assertEqual(tech_research["topicPath"], "research/tech-news")
        self.assertEqual(tech_research["kind"], "research")

        jobs_research = next(
            item
            for item in manifest["automations"]
            if item["id"] == "pavbot-llm-ai-jobs-wroclaw-research"
        )
        self.assertEqual(jobs_research["topic"], "llm-ai-jobs-wroclaw")
        self.assertEqual(jobs_research["topicPath"], "research/llm-ai-jobs-wroclaw")
        self.assertEqual(jobs_research["kind"], "research")

    def test_manifest_collects_topics_and_all_artifact_types(self) -> None:
        generator = load_generator()

        manifest = generator.build_manifest(
            self.repo_root,
            raw_base_url=self.raw_base_url,
        )

        topic_slugs = {topic["slug"] for topic in manifest["topics"]}
        self.assertIn("tech-news", topic_slugs)
        self.assertIn("polska-swiat", topic_slugs)
        self.assertIn("llm-ai-jobs-wroclaw", topic_slugs)

        artifacts = manifest["artifacts"]
        by_path = {artifact["path"]: artifact for artifact in artifacts}
        self.assertEqual(
            by_path["research/tech-news/runs/2026-06-22.md"]["type"],
            "run",
        )
        self.assertEqual(
            by_path["research/tech-news/pdfs/2026-06-22-tech-news.pdf"]["type"],
            "pdf",
        )
        self.assertEqual(
            by_path["research/tech-news/podcasts/2026-06-22/podcast.mp3"]["type"],
            "podcastAudio",
        )
        self.assertEqual(
            by_path["research/tech-news/backlog.md"]["type"],
            "backlog",
        )
        self.assertEqual(
            by_path["research/tech-news/index.md"]["type"],
            "index",
        )
        self.assertEqual(
            by_path["research/tech-news/topic.md"]["type"],
            "topic",
        )
        self.assertEqual(
            by_path[
                "research/codex-agent-automation/proposals/2026-06-17-docs-network-access.md"
            ]["type"],
            "proposal",
        )

        timed_run = by_path["research/llm-ai-jobs-wroclaw/runs/2026-06-20-2152.md"]
        self.assertEqual(timed_run["date"], "2026-06-20")
        self.assertEqual(timed_run["time"], "21:52")

    def test_manifest_uses_public_raw_urls_and_json_serializes(self) -> None:
        generator = load_generator()

        manifest = generator.build_manifest(
            self.repo_root,
            raw_base_url=self.raw_base_url,
        )

        artifact = next(
            item
            for item in manifest["artifacts"]
            if item["path"] == "research/tech-news/runs/2026-06-22.md"
        )
        self.assertEqual(
            artifact["url"],
            "https://raw.githubusercontent.com/example/pavbot/main/research/tech-news/runs/2026-06-22.md",
        )
        self.assertGreater(artifact["sizeBytes"], 0)

        encoded = json.dumps(manifest, ensure_ascii=False)
        self.assertIn("Pavbot", encoded)

    def test_manifest_url_env_resolves_repo_root_raw_base_url(self) -> None:
        generator = load_generator()

        with patch.dict(
            "os.environ",
            {
                "PAVBOT_MANIFEST_URL": "https://raw.githubusercontent.com/example/pavbot/main/public/pavbot-manifest.json",
            },
            clear=True,
        ), patch.object(sys, "argv", ["generate_pavbot_manifest.py"]):
            args = generator.parse_args()

        self.assertEqual(
            generator.resolve_raw_base_url(args.raw_base_url, args.manifest_url),
            "https://raw.githubusercontent.com/example/pavbot/main/",
        )

    def test_raw_base_url_takes_precedence_over_manifest_url(self) -> None:
        generator = load_generator()

        with patch.object(
            sys,
            "argv",
            [
                "generate_pavbot_manifest.py",
                "--raw-base-url",
                "https://raw.githubusercontent.com/example/override/main/",
                "--manifest-url",
                "https://raw.githubusercontent.com/example/pavbot/main/public/pavbot-manifest.json",
            ],
        ):
            args = generator.parse_args()

        self.assertEqual(
            generator.resolve_raw_base_url(args.raw_base_url, args.manifest_url),
            "https://raw.githubusercontent.com/example/override/main/",
        )

    def test_raw_base_url_env_takes_precedence_over_manifest_url_env(self) -> None:
        generator = load_generator()

        with patch.dict(
            "os.environ",
            {
                "PAVBOT_RAW_BASE_URL": "https://raw.githubusercontent.com/example/env-override/main/",
                "PAVBOT_MANIFEST_URL": "https://raw.githubusercontent.com/example/pavbot/main/public/pavbot-manifest.json",
            },
            clear=True,
        ), patch.object(sys, "argv", ["generate_pavbot_manifest.py"]):
            args = generator.parse_args()

        self.assertEqual(
            generator.resolve_raw_base_url(args.raw_base_url, args.manifest_url),
            "https://raw.githubusercontent.com/example/env-override/main/",
        )

    def test_invalid_manifest_url_raises_clear_error(self) -> None:
        generator = load_generator()

        with self.assertRaisesRegex(
            ValueError,
            "PAVBOT_MANIFEST_URL must be a public GitHub raw manifest URL",
        ):
            generator.resolve_raw_base_url(
                "",
                "https://github.com/example/pavbot/blob/main/public/pavbot-manifest.json",
            )

    def test_cli_rejects_invalid_manifest_url_with_clear_error(self) -> None:
        script_path = (
            Path(__file__).resolve().parents[1]
            / "scripts"
            / "generate_pavbot_manifest.py"
        )
        with tempfile.TemporaryDirectory() as tmp:
            env = os.environ.copy()
            env.pop("PAVBOT_RAW_BASE_URL", None)
            env["PAVBOT_MANIFEST_URL"] = (
                "https://github.com/example/pavbot/blob/main/public/pavbot-manifest.json"
            )
            result = subprocess.run(
                [
                    sys.executable,
                    str(script_path),
                    "--repo-root",
                    str(self.repo_root),
                    "--output",
                    str(Path(tmp) / "manifest.json"),
                ],
                capture_output=True,
                env=env,
                text=True,
                check=False,
            )

        self.assertNotEqual(result.returncode, 0)
        self.assertIn(
            "PAVBOT_MANIFEST_URL must be a public GitHub raw manifest URL",
            result.stderr,
        )

    def test_cli_accepts_absolute_output_path_outside_repo(self) -> None:
        script_path = (
            Path(__file__).resolve().parents[1]
            / "scripts"
            / "generate_pavbot_manifest.py"
        )
        with tempfile.TemporaryDirectory() as tmp:
            output_path = Path(tmp) / "manifest.json"
            env = os.environ.copy()
            env.pop("PAVBOT_RAW_BASE_URL", None)
            env["PAVBOT_MANIFEST_URL"] = (
                "https://raw.githubusercontent.com/example/pavbot/main/public/pavbot-manifest.json"
            )
            result = subprocess.run(
                [
                    sys.executable,
                    str(script_path),
                    "--repo-root",
                    str(self.repo_root),
                    "--output",
                    str(output_path),
                ],
                capture_output=True,
                env=env,
                text=True,
                check=False,
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertTrue(output_path.exists())

        self.assertIn("manifest written:", result.stdout)

    def test_manifest_collects_podcast_audio_variants_from_audio_subfolders(self) -> None:
        generator = load_generator()

        with tempfile.TemporaryDirectory() as tmp:
            repo_root = Path(tmp)
            topic_dir = repo_root / "research" / "aktualne-wydarzenia-mobile"
            podcast_dir = topic_dir / "podcasts" / "2026-06-23"
            female_audio = podcast_dir / "audio" / "female-piper" / "podcast.mp3"
            male_audio = podcast_dir / "audio" / "male-xtts" / "podcast.mp3"
            female_audio.parent.mkdir(parents=True)
            male_audio.parent.mkdir(parents=True)
            (topic_dir / "topic.md").parent.mkdir(parents=True, exist_ok=True)
            (topic_dir / "topic.md").write_text(
                "# Topic Contract: aktualne-wydarzenia-mobile\n",
                encoding="utf-8",
            )
            female_audio.write_bytes(b"female mp3")
            male_audio.write_bytes(b"male mp3")
            (podcast_dir / "tts_variants.json").write_text(
                '{"language": "pl"}\n',
                encoding="utf-8",
            )

            manifest = generator.build_manifest(repo_root)

        by_path = {artifact["path"]: artifact for artifact in manifest["artifacts"]}
        self.assertEqual(
            by_path[
                "research/aktualne-wydarzenia-mobile/podcasts/2026-06-23/audio/female-piper/podcast.mp3"
            ]["type"],
            "podcastAudioVariant",
        )
        self.assertEqual(
            by_path[
                "research/aktualne-wydarzenia-mobile/podcasts/2026-06-23/audio/male-xtts/podcast.mp3"
            ]["title"],
            "Podcast audio - male xtts",
        )
        self.assertEqual(
            by_path[
                "research/aktualne-wydarzenia-mobile/podcasts/2026-06-23/tts_variants.json"
            ]["type"],
            "podcastTtsVariants",
        )


if __name__ == "__main__":
    unittest.main()
