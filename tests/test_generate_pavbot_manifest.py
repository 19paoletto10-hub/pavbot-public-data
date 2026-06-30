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
        self.assertIn("pavbot-tech-research-19-33", automation_ids)
        self.assertIn("pavbot-tech-podcast-09-00", automation_ids)
        self.assertIn("pavbot-polska-wiat-research-08-30", automation_ids)
        self.assertIn("pavbot-polska-wiat-research-19-33", automation_ids)
        self.assertIn("pavbot-polska-wiat-podcast-09-30", automation_ids)
        self.assertIn("pavbot-llm-ai-jobs-wroclaw-research", automation_ids)
        self.assertIn("pavbot-aktualne-wydarzenia-mobile-19-33", automation_ids)
        self.assertIn("pavbot-reddit-safari-humor-radar", automation_ids)
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

        tech_evening = next(
            item
            for item in manifest["automations"]
            if item["id"] == "pavbot-tech-research-19-33"
        )
        self.assertEqual(tech_evening["topic"], "tech-news")
        self.assertEqual(tech_evening["cadence"], "daily at 19:33 Europe/Warsaw")
        self.assertEqual(
            tech_evening["output"],
            "research/tech-news/runs/YYYY-MM-DD-HHMM.md",
        )

        polska_evening = next(
            item
            for item in manifest["automations"]
            if item["id"] == "pavbot-polska-wiat-research-19-33"
        )
        self.assertEqual(polska_evening["topic"], "polska-swiat")
        self.assertEqual(polska_evening["cadence"], "daily at 19:33 Europe/Warsaw")
        self.assertEqual(
            polska_evening["output"],
            "research/polska-swiat/runs/YYYY-MM-DD-HHMM.md",
        )

        aktualne_evening = next(
            item
            for item in manifest["automations"]
            if item["id"] == "pavbot-aktualne-wydarzenia-mobile-19-33"
        )
        self.assertEqual(aktualne_evening["topic"], "aktualne-wydarzenia-mobile")
        self.assertEqual(aktualne_evening["kind"], "researchAudio")
        self.assertEqual(aktualne_evening["cadence"], "daily at 19:33 Europe/Warsaw")

        reddit_radar = next(
            item
            for item in manifest["automations"]
            if item["id"] == "pavbot-reddit-safari-humor-radar"
        )
        self.assertEqual(reddit_radar["topic"], "reddit-radar")
        self.assertEqual(reddit_radar["kind"], "automation")
        self.assertEqual(
            reddit_radar["output"],
            "research/reddit-radar/runs/YYYY-MM-DD-HHMM-reddit-radar.md",
        )

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

    def test_manifest_collects_llm_jobs_data_json_as_jobs_data(self) -> None:
        generator = load_generator()

        with tempfile.TemporaryDirectory() as tmp:
            repo = Path(tmp)
            topic_dir = repo / "research" / "llm-ai-jobs-wroclaw"
            data_dir = topic_dir / "data"
            data_dir.mkdir(parents=True)
            (topic_dir / "topic.md").write_text("# Topic Contract: llm-ai-jobs-wroclaw\n", encoding="utf-8")
            (data_dir / "2026-06-25-0141-jobs.json").write_text(
                json.dumps(
                    {
                        "schemaVersion": 1,
                        "status": "Material update",
                        "runDate": "2026-06-25",
                        "runTime": "01:41",
                        "executiveSummary": "Nowe oferty AI.",
                        "opportunities": [
                            {
                                "rank": 1,
                                "title": "Principal AI Engineer",
                                "company": "CKSource",
                                "location": "Remote Poland",
                                "workMode": "Remote",
                                "compensation": "38 000-45 000 PLN",
                                "seniority": "Principal",
                                "fitSummary": "Agentic workflows",
                                "whyInteresting": "Silny fit LLM",
                                "uncertainty": "Tytuł ma drift",
                                "sourceURLs": ["https://example.com/job"],
                                "tags": ["LLM", "Agentic AI"],
                            }
                        ],
                        "changes": ["Nowa rola"],
                        "risks": [],
                        "recommendedActions": ["Sprawdzić za tydzień"],
                        "checkedSources": [{"title": "CKSource careers", "url": "https://example.com"}],
                    },
                    ensure_ascii=False,
                )
                + "\n",
                encoding="utf-8",
            )

            manifest = generator.build_manifest(repo, raw_base_url=self.raw_base_url)

        artifact = next(
            item
            for item in manifest["artifacts"]
            if item["path"] == "research/llm-ai-jobs-wroclaw/data/2026-06-25-0141-jobs.json"
        )
        self.assertEqual(artifact["type"], "jobsData")
        self.assertEqual(artifact["topic"], "llm-ai-jobs-wroclaw")
        self.assertEqual(artifact["date"], "2026-06-25")
        self.assertEqual(artifact["time"], "01:41")
        self.assertEqual(artifact["title"], "Jobs data")

    def test_manifest_collects_research_data_json_for_research_topics(self) -> None:
        generator = load_generator()

        with tempfile.TemporaryDirectory() as tmp:
            repo = Path(tmp)
            topic_dir = repo / "research" / "tech-news"
            data_dir = topic_dir / "data"
            data_dir.mkdir(parents=True)
            (topic_dir / "topic.md").write_text("# Topic Contract: tech-news\n", encoding="utf-8")
            (data_dir / "2026-06-25-research.json").write_text(
                json.dumps(
                    {
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
                    },
                    ensure_ascii=False,
                )
                + "\n",
                encoding="utf-8",
            )
            (data_dir / "2026-06-25-1933-research.json").write_text(
                json.dumps(
                    {
                        "schemaVersion": 1,
                        "topic": "tech-news",
                        "runDate": "2026-06-25",
                        "runTime": "19:33",
                        "status": "Material update",
                        "leadParagraphs": ["Wieczorne wydanie AI i infrastruktury."],
                        "summaryBullets": ["AI: wieczorny update."],
                        "articles": [
                            {
                                "id": "tech-evening-1",
                                "section": "AI",
                                "title": "Wieczorny update AI",
                                "standfirst": "Wieczorny update AI.",
                                "whatHappened": "Pojawił się wieczorny update AI.",
                                "whyItMatters": "To ważne dla wieczornego monitoringu.",
                                "deeperAnalysis": ["Analiza pierwsza.", "Analiza druga."],
                                "contextPoints": ["Co się stało: test.", "Dlaczego ważne: test."],
                                "sources": [{"title": "OpenAI", "url": "https://openai.com/news"}],
                                "priority": "High",
                                "tags": ["AI"],
                            }
                        ],
                        "podcastTopics": [],
                        "checkedSources": [{"title": "OpenAI", "url": "https://openai.com/news"}],
                    },
                    ensure_ascii=False,
                )
                + "\n",
                encoding="utf-8",
            )

            manifest = generator.build_manifest(repo, raw_base_url=self.raw_base_url)

        artifact = next(
            item
            for item in manifest["artifacts"]
            if item["path"] == "research/tech-news/data/2026-06-25-research.json"
        )
        self.assertEqual(artifact["type"], "researchData")
        self.assertEqual(artifact["topic"], "tech-news")
        self.assertEqual(artifact["date"], "2026-06-25")
        self.assertEqual(artifact["title"], "Research data")

        evening_artifact = next(
            item
            for item in manifest["artifacts"]
            if item["path"] == "research/tech-news/data/2026-06-25-1933-research.json"
        )
        self.assertEqual(evening_artifact["type"], "researchData")
        self.assertEqual(evening_artifact["date"], "2026-06-25")
        self.assertEqual(evening_artifact["time"], "19:33")

    def test_manifest_ignores_finder_style_duplicate_artifacts(self) -> None:
        generator = load_generator()

        with tempfile.TemporaryDirectory() as tmp:
            repo = Path(tmp)
            topic_dir = repo / "research" / "polska-swiat"
            (topic_dir / "topic.md").parent.mkdir(parents=True)
            (topic_dir / "topic.md").write_text("# Topic Contract: polska-swiat\n", encoding="utf-8")
            (topic_dir / "data").mkdir()
            (topic_dir / "pdfs").mkdir()
            (topic_dir / "podcasts" / "2026-06-27").mkdir(parents=True)

            (topic_dir / "data" / "2026-06-27-research.json").write_text("{}\n", encoding="utf-8")
            (topic_dir / "data" / "2026-06-27-research 2.json").write_text("{}\n", encoding="utf-8")
            (topic_dir / "pdfs" / "2026-06-27-polska-swiat.pdf").write_bytes(b"%PDF canonical")
            (topic_dir / "pdfs" / "2026-06-27-polska-swiat 2.pdf").write_bytes(b"%PDF duplicate")
            (topic_dir / "podcasts" / "2026-06-27" / "script.md").write_text("# Script\n", encoding="utf-8")
            (topic_dir / "podcasts" / "2026-06-27" / "script 2.md").write_text("# Script duplicate\n", encoding="utf-8")
            (topic_dir / "podcasts" / "2026-06-27" / "brief.pdf").write_bytes(b"%PDF brief")
            (topic_dir / "podcasts" / "2026-06-27" / "brief 2.pdf").write_bytes(b"%PDF brief duplicate")

            manifest = generator.build_manifest(repo, raw_base_url=self.raw_base_url)

        paths = {artifact["path"] for artifact in manifest["artifacts"]}
        self.assertIn("research/polska-swiat/data/2026-06-27-research.json", paths)
        self.assertIn("research/polska-swiat/pdfs/2026-06-27-polska-swiat.pdf", paths)
        self.assertIn("research/polska-swiat/podcasts/2026-06-27/script.md", paths)
        self.assertIn("research/polska-swiat/podcasts/2026-06-27/brief.pdf", paths)
        self.assertNotIn("research/polska-swiat/data/2026-06-27-research 2.json", paths)
        self.assertNotIn("research/polska-swiat/pdfs/2026-06-27-polska-swiat 2.pdf", paths)
        self.assertNotIn("research/polska-swiat/podcasts/2026-06-27/script 2.md", paths)
        self.assertNotIn("research/polska-swiat/podcasts/2026-06-27/brief 2.pdf", paths)

    def test_manifest_collects_mobile_news_data_json_for_mobile_topic(self) -> None:
        generator = load_generator()

        with tempfile.TemporaryDirectory() as tmp:
            repo = Path(tmp)
            topic_dir = repo / "research" / "aktualne-wydarzenia-mobile"
            data_dir = topic_dir / "data"
            pdf_dir = topic_dir / "pdfs"
            audio_dir = topic_dir / "podcasts" / "2026-06-25-1015" / "audio" / "female-piper"
            data_dir.mkdir(parents=True)
            pdf_dir.mkdir(parents=True)
            audio_dir.mkdir(parents=True)
            (topic_dir / "topic.md").write_text(
                "# Topic Contract: aktualne-wydarzenia-mobile\n",
                encoding="utf-8",
            )
            (data_dir / "2026-06-25-1015-mobile-news.json").write_text(
                json.dumps(
                    {
                        "schemaVersion": 1,
                        "topic": "aktualne-wydarzenia-mobile",
                        "runDate": "2026-06-25",
                        "runTime": "10:15",
                        "status": "Material update",
                        "headline": "Wydanie dnia",
                        "leadParagraphs": ["Najważniejsze wydarzenia dnia."],
                        "sections": [
                            {
                                "id": "polska",
                                "title": "Polska",
                                "summary": "Najważniejsze krajowe sygnały.",
                                "articles": [
                                    {
                                        "id": "polska-1",
                                        "section": "Polska",
                                        "title": "Gdańsk gospodarzem rozmów",
                                        "lead": "Polska wzmacnia rolę gospodarza rozmów.",
                                        "facts": ["KPRM zapowiedziało spotkanie."],
                                        "analysis": "To zwiększa wagę dyplomatyczną dnia.",
                                        "whyItMatters": "Użytkownik widzi, co realnie zmienia się w otoczeniu.",
                                        "sources": [{"title": "KPRM", "url": "https://www.gov.pl/web/premier"}],
                                        "tags": ["Polska"],
                                        "ttsText": "Polska wzmacnia rolę gospodarza rozmów. To zwiększa wagę dyplomatyczną dnia.",
                                        "priority": "High",
                                    }
                                ],
                            }
                        ],
                        "checkedSources": [{"title": "KPRM", "url": "https://www.gov.pl/web/premier"}],
                        "audioArtifacts": [],
                    },
                    ensure_ascii=False,
                )
                + "\n",
                encoding="utf-8",
            )
            (pdf_dir / "2026-06-25-1015-mobile-brief.pdf").write_bytes(b"%PDF mobile brief")
            (audio_dir / "podcast.mp3").write_bytes(b"mp3")

            manifest = generator.build_manifest(repo, raw_base_url=self.raw_base_url)

        by_path = {artifact["path"]: artifact for artifact in manifest["artifacts"]}
        artifact = by_path["research/aktualne-wydarzenia-mobile/data/2026-06-25-1015-mobile-news.json"]
        self.assertEqual(artifact["type"], "mobileNewsData")
        self.assertEqual(artifact["topic"], "aktualne-wydarzenia-mobile")
        self.assertEqual(artifact["date"], "2026-06-25")
        self.assertEqual(artifact["time"], "10:15")
        self.assertEqual(artifact["title"], "Mobile news data")

    def test_manifest_collects_pulse_news_data_json_for_pulse_topic(self) -> None:
        generator = load_generator()

        with tempfile.TemporaryDirectory() as tmp:
            repo = Path(tmp)
            topic_dir = repo / "research" / "puls-dnia-news"
            data_dir = topic_dir / "data"
            data_dir.mkdir(parents=True)
            (topic_dir / "topic.md").write_text(
                "# Topic Contract: puls-dnia-news\n",
                encoding="utf-8",
            )
            (data_dir / "2026-06-26-1200-pulse-news.json").write_text(
                json.dumps(
                    {
                        "schemaVersion": 1,
                        "topic": "puls-dnia-news",
                        "runDate": "2026-06-26",
                        "runTime": "12:00",
                        "status": "Material update",
                        "headline": "Puls dnia",
                        "summary": "Najważniejsze tematy z ostatnich godzin.",
                        "items": [{"id": "one"}, {"id": "two"}],
                        "checkedSources": [],
                    },
                    ensure_ascii=False,
                )
                + "\n",
                encoding="utf-8",
            )

            manifest = generator.build_manifest(repo, raw_base_url=self.raw_base_url)

        artifact = next(
            item
            for item in manifest["artifacts"]
            if item["path"] == "research/puls-dnia-news/data/2026-06-26-1200-pulse-news.json"
        )
        self.assertEqual(artifact["type"], "pulseNewsData")
        self.assertEqual(artifact["topic"], "puls-dnia-news")
        self.assertEqual(artifact["date"], "2026-06-26")
        self.assertEqual(artifact["time"], "12:00")
        self.assertEqual(artifact["title"], "Pulse news data")
        self.assertEqual(artifact["itemCount"], 2)

    def test_manifest_collects_pulse_news_data_without_topic_file(self) -> None:
        generator = load_generator()

        with tempfile.TemporaryDirectory() as tmp:
            repo = Path(tmp)
            data_dir = repo / "research" / "puls-dnia-news" / "data"
            data_dir.mkdir(parents=True)
            (data_dir / "2026-06-26-1502-pulse-news.json").write_text(
                json.dumps(
                    {
                        "schemaVersion": 1,
                        "topic": "puls-dnia-news",
                        "runDate": "2026-06-26",
                        "runTime": "15:02",
                        "status": "Material update",
                        "headline": "Puls dnia",
                        "summary": "Najważniejsze tematy z ostatnich godzin.",
                        "items": [],
                        "checkedSources": [],
                    },
                    ensure_ascii=False,
                )
                + "\n",
                encoding="utf-8",
            )

            manifest = generator.build_manifest(repo, raw_base_url=self.raw_base_url)

        topic = next(item for item in manifest["topics"] if item["slug"] == "puls-dnia-news")
        self.assertEqual(topic["title"], "Pavbot Puls Dnia News")
        artifact = next(
            item
            for item in manifest["artifacts"]
            if item["path"] == "research/puls-dnia-news/data/2026-06-26-1502-pulse-news.json"
        )
        self.assertEqual(artifact["type"], "pulseNewsData")
        self.assertEqual(artifact["topic"], "puls-dnia-news")
        self.assertEqual(artifact["time"], "15:02")

    def test_manifest_collects_reddit_radar_run_and_public_data_json(self) -> None:
        generator = load_generator()

        with tempfile.TemporaryDirectory() as tmp:
            repo = Path(tmp)
            topic_dir = repo / "research" / "reddit-radar"
            runs_dir = topic_dir / "runs"
            data_dir = topic_dir / "data"
            runs_dir.mkdir(parents=True)
            data_dir.mkdir(parents=True)
            (topic_dir / "topic.md").write_text("# Topic Contract: reddit-radar\n", encoding="utf-8")
            (runs_dir / "2026-06-28-0206-reddit-radar.md").write_text(
                "# Reddit Radar 2026-06-28-0206\n",
                encoding="utf-8",
            )
            (data_dir / "2026-06-28-0206-reddit-radar.json").write_text(
                json.dumps({"schemaVersion": 1, "id": "humor-2026-06-28-0206"}, ensure_ascii=False) + "\n",
                encoding="utf-8",
            )
            (data_dir / "2026-06-28-0206-reddit-radar-raw.json").write_text(
                json.dumps({"schemaVersion": 1, "raw": True}, ensure_ascii=False) + "\n",
                encoding="utf-8",
            )
            (data_dir / "reddit-radar-state.json").write_text(
                json.dumps({"items": []}, ensure_ascii=False) + "\n",
                encoding="utf-8",
            )

            manifest = generator.build_manifest(repo, raw_base_url=self.raw_base_url)

        by_path = {artifact["path"]: artifact for artifact in manifest["artifacts"]}
        self.assertEqual(
            by_path["research/reddit-radar/runs/2026-06-28-0206-reddit-radar.md"]["type"],
            "run",
        )
        self.assertEqual(
            by_path["research/reddit-radar/data/2026-06-28-0206-reddit-radar.json"]["type"],
            "redditRadarData",
        )
        self.assertEqual(
            by_path["research/reddit-radar/data/2026-06-28-0206-reddit-radar-raw.json"]["type"],
            "redditRadarRawData",
        )
        self.assertEqual(
            by_path["research/reddit-radar/data/2026-06-28-0206-reddit-radar.json"]["time"],
            "02:06",
        )
        self.assertNotIn("research/reddit-radar/data/reddit-radar-state.json", by_path)

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

    def test_write_manifest_preserves_generated_at_when_payload_is_unchanged(self) -> None:
        generator = load_generator()

        with tempfile.TemporaryDirectory() as tmp:
            repo_root = Path(tmp)
            docs_dir = repo_root / "docs"
            topic_dir = repo_root / "research" / "tech-news"
            docs_dir.mkdir(parents=True)
            topic_dir.mkdir(parents=True)
            (docs_dir / "how-to-use.md").write_text("# How To Use Pavbot\n", encoding="utf-8")
            (topic_dir / "topic.md").write_text("# Topic Contract: tech-news\n", encoding="utf-8")

            output_path = repo_root / "public" / "pavbot-manifest.json"
            first_manifest = generator.build_manifest(repo_root, raw_base_url=self.raw_base_url)
            first_manifest["generatedAt"] = "2026-06-22T00:00:00+00:00"
            generator.write_manifest(first_manifest, output_path)
            first_text = output_path.read_text(encoding="utf-8")

            second_manifest = generator.build_manifest(repo_root, raw_base_url=self.raw_base_url)
            generator.write_manifest(second_manifest, output_path)
            second_text = output_path.read_text(encoding="utf-8")
            payload = json.loads(second_text)

            self.assertEqual(payload["generatedAt"], "2026-06-22T00:00:00+00:00")
            self.assertEqual(second_text, first_text)

    def test_manifest_uses_explicit_automation_kind_from_docs(self) -> None:
        generator = load_generator()

        with tempfile.TemporaryDirectory() as tmp:
            repo_root = Path(tmp)
            docs_dir = repo_root / "docs"
            topic_dir = repo_root / "research" / "aktualne-wydarzenia-mobile"
            docs_dir.mkdir(parents=True)
            topic_dir.mkdir(parents=True)
            (topic_dir / "topic.md").write_text(
                "# Topic Contract: aktualne-wydarzenia-mobile\n",
                encoding="utf-8",
            )
            (docs_dir / "how-to-use.md").write_text(
                """# How To Use Pavbot

The current active automations are:

- Name: `Pavbot Aktualne Wydarzenia Mobile 10:15`
- ID: `pavbot-aktualne-wydarzenia-mobile-10-15`
- Kind: `researchAudio`
- Topic: `research/aktualne-wydarzenia-mobile`
- Cadence: daily at 10:15 local time
- Output: `research/aktualne-wydarzenia-mobile/pdfs/YYYY-MM-DD-mobile-brief.pdf`

## Later
""",
                encoding="utf-8",
            )

            manifest = generator.build_manifest(repo_root)

        automation = manifest["automations"][0]
        self.assertEqual(automation["kind"], "researchAudio")
        self.assertEqual(automation["topic"], "aktualne-wydarzenia-mobile")

    def test_manifest_collects_only_mobile_public_audio_variants_from_audio_subfolders(self) -> None:
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
            (female_audio.parent / "podcast.raw.mp3").write_bytes(b"raw female mp3")
            (male_audio.parent / "podcast.raw.mp3").write_bytes(b"raw male mp3")
            (female_audio.parent / "render.log").write_text("ok\n", encoding="utf-8")
            (male_audio.parent / "render.log").write_text("ok\n", encoding="utf-8")
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
        self.assertNotIn(
            "research/aktualne-wydarzenia-mobile/podcasts/2026-06-23/tts_variants.json",
            by_path,
        )
        self.assertNotIn(
            "research/aktualne-wydarzenia-mobile/podcasts/2026-06-23/audio/female-piper/podcast.raw.mp3",
            by_path,
        )
        self.assertNotIn(
            "research/aktualne-wydarzenia-mobile/podcasts/2026-06-23/audio/male-xtts/render.log",
            by_path,
        )

    def test_manifest_collects_only_public_mobile_pdf_and_audio_artifacts(self) -> None:
        generator = load_generator()

        with tempfile.TemporaryDirectory() as tmp:
            repo_root = Path(tmp)
            topic_dir = repo_root / "research" / "aktualne-wydarzenia-mobile"
            run_path = topic_dir / "runs" / "2026-06-23-1015.md"
            pdf_path = topic_dir / "pdfs" / "2026-06-23-1015-mobile-brief.pdf"
            newspaper_pdf_path = topic_dir / "pdfs" / "2026-06-23-1015-newspaper.pdf"
            data_path = topic_dir / "data" / "2026-06-23-1015-mobile-news.json"
            podcast_dir = topic_dir / "podcasts" / "2026-06-23-1015"
            female_audio = podcast_dir / "audio" / "female-piper" / "podcast.mp3"
            female_render = podcast_dir / "audio" / "female-piper" / "render.json"

            female_audio.parent.mkdir(parents=True)
            run_path.parent.mkdir(parents=True)
            pdf_path.parent.mkdir(parents=True)
            (topic_dir / "topic.md").write_text(
                "# Topic Contract: aktualne-wydarzenia-mobile\n",
                encoding="utf-8",
            )
            run_path.write_text("# Mobile report\n", encoding="utf-8")
            pdf_path.write_bytes(b"%PDF timestamped mobile brief")
            newspaper_pdf_path.write_bytes(b"%PDF timestamped mobile newspaper")
            data_path.parent.mkdir(parents=True)
            data_path.write_text(
                json.dumps(
                    {
                        "schemaVersion": 1,
                        "topic": "aktualne-wydarzenia-mobile",
                        "runDate": "2026-06-23",
                        "runTime": "10:15",
                        "status": "Material update",
                        "headline": "Wydanie",
                        "leadParagraphs": ["Lead"],
                        "sections": [
                            {
                                "id": "ogolne",
                                "title": "Ogólne",
                                "summary": "Sygnały dnia.",
                                "articles": [
                                    {
                                        "id": "a1",
                                        "section": "Ogólne",
                                        "title": "Test",
                                        "lead": "Lead",
                                        "facts": ["Fakt"],
                                        "analysis": "Analiza",
                                        "whyItMatters": "Znaczenie",
                                        "sources": [{"title": "Źródło", "url": "https://example.com"}],
                                        "tags": ["Ogólne"],
                                        "ttsText": "Lead. Analiza. Znaczenie.",
                                        "priority": "High",
                                    }
                                ],
                            }
                        ],
                        "checkedSources": [{"title": "Źródło", "url": "https://example.com"}],
                        "audioArtifacts": [],
                    },
                    ensure_ascii=False,
                )
                + "\n",
                encoding="utf-8",
            )
            (podcast_dir / "script.md").write_text("# Script\n", encoding="utf-8")
            (podcast_dir / "sources.md").write_text("# Sources\n", encoding="utf-8")
            (podcast_dir / "tts_variants.json").write_text(
                '{"language": "pl"}\n',
                encoding="utf-8",
            )
            female_audio.write_bytes(b"female mp3")
            female_render.write_text('{"status": "ok"}\n', encoding="utf-8")
            (female_audio.parent / "podcast.raw.mp3").write_bytes(b"raw mp3")
            (female_audio.parent / "render.log").write_text("raw log\n", encoding="utf-8")

            manifest = generator.build_manifest(repo_root)

        by_path = {artifact["path"]: artifact for artifact in manifest["artifacts"]}
        expected = {
            "research/aktualne-wydarzenia-mobile/pdfs/2026-06-23-1015-mobile-brief.pdf": "pdf",
            "research/aktualne-wydarzenia-mobile/pdfs/2026-06-23-1015-newspaper.pdf": "pdf",
            "research/aktualne-wydarzenia-mobile/data/2026-06-23-1015-mobile-news.json": "mobileNewsData",
            "research/aktualne-wydarzenia-mobile/podcasts/2026-06-23-1015/script.md": "podcastScript",
            "research/aktualne-wydarzenia-mobile/podcasts/2026-06-23-1015/audio/female-piper/podcast.mp3": "podcastAudioVariant",
        }
        for path, artifact_type in expected.items():
            with self.subTest(path=path):
                self.assertEqual(by_path[path]["type"], artifact_type)
                self.assertEqual(by_path[path]["date"], "2026-06-23")
                self.assertEqual(by_path[path]["time"], "10:15")

        for path in (
            "research/aktualne-wydarzenia-mobile/runs/2026-06-23-1015.md",
            "research/aktualne-wydarzenia-mobile/podcasts/2026-06-23-1015/sources.md",
            "research/aktualne-wydarzenia-mobile/podcasts/2026-06-23-1015/tts_variants.json",
            "research/aktualne-wydarzenia-mobile/podcasts/2026-06-23-1015/audio/female-piper/render.json",
        ):
            with self.subTest(path=path):
                self.assertNotIn(path, by_path)

        self.assertNotIn(
            "research/aktualne-wydarzenia-mobile/podcasts/2026-06-23-1015/audio/female-piper/podcast.raw.mp3",
            by_path,
        )
        self.assertNotIn(
            "research/aktualne-wydarzenia-mobile/podcasts/2026-06-23-1015/audio/female-piper/render.log",
            by_path,
        )

    def test_mobile_automation_contract_documents_single_warsaw_run_stamp(self) -> None:
        automation_prompt = (
            self.repo_root
            / "research"
            / "aktualne-wydarzenia-mobile"
            / "automation-prompt.md"
        ).read_text(encoding="utf-8")
        how_to_use = (self.repo_root / "docs" / "how-to-use.md").read_text(
            encoding="utf-8"
        )

        self.assertIn(
            "RUN_STAMP=$(TZ=Europe/Warsaw date +%Y-%m-%d-%H%M)",
            automation_prompt,
        )
        self.assertIn("RUN_DATE=${RUN_STAMP:0:10}", automation_prompt)
        for expected_path in (
            "runs/YYYY-MM-DD-HHMM.md",
            "pdfs/YYYY-MM-DD-HHMM-mobile-brief.pdf",
            "pdfs/YYYY-MM-DD-HHMM-newspaper.pdf",
            "podcasts/YYYY-MM-DD-HHMM/",
        ):
            with self.subTest(expected_path=expected_path):
                self.assertIn(expected_path, automation_prompt)
                self.assertIn(expected_path, how_to_use)


if __name__ == "__main__":
    unittest.main()
