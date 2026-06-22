from __future__ import annotations

import importlib.util
import json
import unittest
from pathlib import Path


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


if __name__ == "__main__":
    unittest.main()
