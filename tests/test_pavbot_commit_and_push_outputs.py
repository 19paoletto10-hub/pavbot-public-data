from __future__ import annotations

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
            local_head = self.git(repo, "rev-parse", "HEAD", stdout=True).strip()
            remote_head = self.git(repo, "ls-remote", "origin", "refs/heads/main", stdout=True).split()[0]
            self.assertEqual(local_head, remote_head)

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

    def temporary_repo(self):
        return TemporaryPavbotRepo(self.repo_root, self.script_path)

    def run_publish_script(self, repo: Path, topic_path: str) -> subprocess.CompletedProcess[str]:
        self.assertTrue(self.script_path.exists(), f"missing script: {self.script_path}")
        env = os.environ.copy()
        env["PAVBOT_MANIFEST_URL"] = (
            "https://raw.githubusercontent.com/example/pavbot/main/public/pavbot-manifest.json"
        )
        return subprocess.run(
            ["bash", str(self.script_path), topic_path],
            cwd=repo,
            capture_output=True,
            env=env,
            text=True,
            check=False,
        )

    def write_topic_artifact(self, repo: Path, topic: str, relative_path: str, content: str) -> None:
        path = repo / "research" / topic / relative_path
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8")

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
        topic = repo / "research" / "tech-news"
        topic.mkdir(parents=True)
        (topic / "topic.md").write_text("# Topic Contract: tech-news\n", encoding="utf-8")
        (topic / "index.md").write_text("# Index\n", encoding="utf-8")
        (topic / "backlog.md").write_text("# Backlog\n", encoding="utf-8")

    def git(self, *args: str) -> None:
        assert self.repo is not None
        subprocess.run(["git", *args], cwd=self.repo, check=True, capture_output=True, text=True)


if __name__ == "__main__":
    unittest.main()
