#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import re
from datetime import datetime, timezone
from pathlib import Path
from typing import Any
from urllib.parse import urlparse


DATE_RE = re.compile(r"(?P<date>\d{4}-\d{2}-\d{2})(?:-(?P<time>\d{4}))?")
DOC_FIELD_RE = re.compile(r"^- (?P<key>Name|ID|Kind|Topic|Cadence|Output): `?(?P<value>.+?)`?$")
MANIFEST_URL_ERROR = (
    "PAVBOT_MANIFEST_URL must be a public GitHub raw manifest URL like "
    "https://raw.githubusercontent.com/<owner>/<repo>/<branch>/public/pavbot-manifest.json"
)
MANIFEST_PATH_SUFFIX = "/public/pavbot-manifest.json"
MOBILE_PUBLIC_ONLY_TOPIC = "aktualne-wydarzenia-mobile"
LLM_JOBS_TOPIC = "llm-ai-jobs-wroclaw"
PULSE_NEWS_TOPIC = "puls-dnia-news"
RESEARCH_DATA_TOPICS = {"tech-news", "polska-swiat"}


def build_manifest(repo_root: Path, raw_base_url: str = "") -> dict[str, Any]:
    repo_root = repo_root.resolve()
    raw_base_url = normalize_base_url(raw_base_url)
    topics = collect_topics(repo_root, raw_base_url)
    return {
        "schemaVersion": 1,
        "title": "Pavbot Automation Manifest",
        "generatedAt": datetime.now(timezone.utc).isoformat(),
        "rawBaseUrl": raw_base_url,
        "automations": collect_automations(repo_root, raw_base_url),
        "topics": topics,
        "artifacts": collect_artifacts(repo_root, raw_base_url, topics),
    }


def collect_automations(repo_root: Path, raw_base_url: str) -> list[dict[str, Any]]:
    docs_path = repo_root / "docs" / "how-to-use.md"
    if not docs_path.exists():
        return []

    lines = docs_path.read_text(encoding="utf-8").splitlines()
    automations: list[dict[str, str]] = []
    current: dict[str, str] = {}
    in_active_section = False

    for line in lines:
        if line.strip() == "The current active automations are:":
            in_active_section = True
            continue
        if in_active_section and line.startswith("## "):
            break
        if not in_active_section:
            continue

        match = DOC_FIELD_RE.match(line.strip())
        if match:
            key = match.group("key").lower()
            if key == "name" and current:
                automations.append(current)
                current = {}
            current[key] = match.group("value")

    if current:
        automations.append(current)

    result: list[dict[str, Any]] = []
    for item in automations:
        topic_path = item.get("topic", "")
        topic_slug = topic_path.removeprefix("research/") if topic_path else ""
        name = item.get("name", "")
        output = item.get("output")
        entry = {
            "id": item.get("id", slugify(name)),
            "name": name,
            "enabled": True,
            "kind": item.get("kind") or infer_automation_kind(name, output),
            "topic": topic_slug,
            "topicPath": topic_path,
            "cadence": item.get("cadence", ""),
            "sourcePath": "docs/how-to-use.md",
            "sourceUrl": raw_url(raw_base_url, "docs/how-to-use.md"),
        }
        if output:
            entry["output"] = output
            entry["outputUrl"] = raw_url(raw_base_url, output)
        result.append(entry)

    return sorted(result, key=lambda item: (item["topic"], item["kind"], item["name"]))


def collect_topics(repo_root: Path, raw_base_url: str) -> list[dict[str, Any]]:
    research_root = repo_root / "research"
    if not research_root.exists():
        return []

    topics: list[dict[str, Any]] = []
    for topic_dir in sorted(path for path in research_root.iterdir() if path.is_dir()):
        if topic_dir.name == "templates":
            continue
        topic_file = topic_dir / "topic.md"
        title = read_markdown_title(topic_file) if topic_file.exists() else None
        if not topic_file.exists() and not has_topic_artifact_fallback(topic_dir):
            continue

        rel_path = relative_path(topic_file, repo_root)
        topics.append(
            {
                "slug": topic_dir.name,
                "title": title or fallback_topic_title(topic_dir.name),
                "path": relative_path(topic_dir, repo_root),
                "topicFilePath": rel_path,
                "url": raw_url(raw_base_url, rel_path),
            }
        )

    return topics


def has_topic_artifact_fallback(topic_dir: Path) -> bool:
    if topic_dir.name == PULSE_NEWS_TOPIC:
        return any((topic_dir / "data").glob("*-pulse-news.json"))
    return False


def fallback_topic_title(slug: str) -> str:
    if slug == PULSE_NEWS_TOPIC:
        return "Pavbot Puls Dnia News"
    return slug


def collect_artifacts(
    repo_root: Path,
    raw_base_url: str,
    topics: list[dict[str, Any]],
) -> list[dict[str, Any]]:
    artifacts: list[dict[str, Any]] = []
    for topic in topics:
        topic_dir = repo_root / topic["path"]
        slug = topic["slug"]

        if slug == MOBILE_PUBLIC_ONLY_TOPIC:
            collect_mobile_public_artifacts(artifacts, repo_root, raw_base_url, topic_dir, slug)
            continue

        for name, artifact_type in (
            ("topic.md", "topic"),
            ("index.md", "index"),
            ("backlog.md", "backlog"),
            ("automation-prompt.md", "automationPrompt"),
            ("automation-research-prompt.md", "automationPrompt"),
            ("automation-podcast-prompt.md", "automationPrompt"),
        ):
            add_artifact(artifacts, repo_root, raw_base_url, topic_dir / name, slug, artifact_type)

        for path in sorted((topic_dir / "runs").glob("*.md")):
            add_artifact(artifacts, repo_root, raw_base_url, path, slug, "run")

        for path in sorted((topic_dir / "pdfs").glob("*.pdf")):
            add_artifact(artifacts, repo_root, raw_base_url, path, slug, "pdf")

        if slug == LLM_JOBS_TOPIC:
            for path in sorted((topic_dir / "data").glob("*.json")):
                add_artifact(artifacts, repo_root, raw_base_url, path, slug, "jobsData")
        elif slug == PULSE_NEWS_TOPIC:
            for path in sorted((topic_dir / "data").glob("*-pulse-news.json")):
                add_artifact(artifacts, repo_root, raw_base_url, path, slug, "pulseNewsData")
        elif slug in RESEARCH_DATA_TOPICS:
            for path in sorted((topic_dir / "data").glob("*.json")):
                add_artifact(artifacts, repo_root, raw_base_url, path, slug, "researchData")

        for path in sorted((topic_dir / "proposals").glob("*.md")):
            add_artifact(artifacts, repo_root, raw_base_url, path, slug, "proposal")

        podcasts_dir = topic_dir / "podcasts"
        if podcasts_dir.exists():
            for date_dir in sorted(path for path in podcasts_dir.iterdir() if path.is_dir()):
                for path in sorted(item for item in date_dir.rglob("*") if item.is_file()):
                    if not is_public_podcast_artifact(path):
                        continue
                    add_artifact(
                        artifacts,
                        repo_root,
                        raw_base_url,
                        path,
                        slug,
                        infer_podcast_artifact_type(path),
                        forced_date=parse_date_parts(date_dir.name),
                    )

    return sorted(
        artifacts,
        key=lambda item: (
            item.get("date") or "",
            item["topic"],
            item["type"],
            item["path"],
        ),
        reverse=True,
    )


def collect_mobile_public_artifacts(
    artifacts: list[dict[str, Any]],
    repo_root: Path,
    raw_base_url: str,
    topic_dir: Path,
    slug: str,
) -> None:
    for path in sorted((topic_dir / "data").glob("*-mobile-news.json")):
        add_artifact(artifacts, repo_root, raw_base_url, path, slug, "mobileNewsData")

    for path in sorted((topic_dir / "pdfs").glob("*-mobile-brief.pdf")):
        add_artifact(artifacts, repo_root, raw_base_url, path, slug, "pdf")

    podcasts_dir = topic_dir / "podcasts"
    if not podcasts_dir.exists():
        return

    for date_dir in sorted(path for path in podcasts_dir.iterdir() if path.is_dir()):
        add_artifact(
            artifacts,
            repo_root,
            raw_base_url,
            date_dir / "script.md",
            slug,
            "podcastScript",
            forced_date=parse_date_parts(date_dir.name),
        )

        for path in sorted(date_dir.glob("audio/*/podcast.mp3")):
            add_artifact(
                artifacts,
                repo_root,
                raw_base_url,
                path,
                slug,
                "podcastAudioVariant",
                forced_date=parse_date_parts(date_dir.name),
            )


def add_artifact(
    artifacts: list[dict[str, Any]],
    repo_root: Path,
    raw_base_url: str,
    path: Path,
    topic: str,
    artifact_type: str,
    forced_date: tuple[str | None, str | None] | None = None,
) -> None:
    if not path.exists() or not path.is_file():
        return

    rel_path = relative_path(path, repo_root)
    date, time = forced_date if forced_date is not None else parse_date_parts(path.stem)
    artifact: dict[str, Any] = {
        "id": rel_path,
        "type": artifact_type,
        "topic": topic,
        "title": artifact_title(path, artifact_type),
        "path": rel_path,
        "url": raw_url(raw_base_url, rel_path),
        "sizeBytes": path.stat().st_size,
    }
    if date:
        artifact["date"] = date
    if time:
        artifact["time"] = time
    artifacts.append(artifact)


def parse_date_parts(value: str) -> tuple[str | None, str | None]:
    match = DATE_RE.search(value)
    if not match:
        return None, None
    time = match.group("time")
    if time:
        time = f"{time[:2]}:{time[2:]}"
    return match.group("date"), time


def infer_automation_kind(name: str, output: str | None) -> str:
    lowered = f"{name} {output or ''}".lower()
    if "podcast" in lowered:
        return "podcast"
    if "research" in lowered:
        return "research"
    return "automation"


def infer_podcast_artifact_type(path: Path) -> str:
    name = path.name
    if name == "podcast.mp3" and path.parent.parent.name == "audio":
        return "podcastAudioVariant"
    if name == "podcast.mp3":
        return "podcastAudio"
    if name == "brief.pdf":
        return "podcastBriefPdf"
    if name == "script.md":
        return "podcastScript"
    if name == "draft.md":
        return "podcastDraft"
    if name == "sources.md":
        return "podcastSources"
    if name == "render.json":
        return "podcastRender"
    if name == "tts_variants.json":
        return "podcastTtsVariants"
    return "podcastArtifact"


def is_public_podcast_artifact(path: Path) -> bool:
    return path.name not in {"podcast.raw.mp3", "render.log"}


def artifact_title(path: Path, artifact_type: str) -> str:
    if path.suffix == ".md":
        title = read_markdown_title(path)
        if title:
            return title
    if artifact_type == "podcastAudio":
        return "Podcast audio"
    if artifact_type == "podcastAudioVariant":
        return "Podcast audio - " + path.parent.name.replace("-", " ")
    if artifact_type == "podcastBriefPdf":
        return "Podcast brief PDF"
    if artifact_type == "podcastTtsVariants":
        return "TTS variants metadata"
    if artifact_type == "jobsData":
        return "Jobs data"
    if artifact_type == "researchData":
        return "Research data"
    if artifact_type == "mobileNewsData":
        return "Mobile news data"
    if artifact_type == "pulseNewsData":
        return "Pulse news data"
    return path.name


def read_markdown_title(path: Path) -> str | None:
    try:
        for line in path.read_text(encoding="utf-8").splitlines():
            if line.startswith("# "):
                return line[2:].strip()
    except UnicodeDecodeError:
        return None
    return None


def raw_url(raw_base_url: str, rel_path: str) -> str:
    return f"{raw_base_url}{rel_path}" if raw_base_url else rel_path


def normalize_base_url(value: str) -> str:
    value = value.strip()
    if not value:
        return ""
    return value if value.endswith("/") else f"{value}/"


def resolve_raw_base_url(raw_base_url: str, manifest_url: str) -> str:
    raw_base_url = normalize_base_url(raw_base_url)
    if raw_base_url:
        return raw_base_url
    manifest_url = manifest_url.strip()
    if not manifest_url:
        return ""
    return raw_base_url_from_manifest_url(manifest_url)


def raw_base_url_from_manifest_url(manifest_url: str) -> str:
    parsed = urlparse(manifest_url.strip())
    if (
        parsed.scheme != "https"
        or parsed.netloc != "raw.githubusercontent.com"
        or parsed.query
        or parsed.fragment
        or not parsed.path.endswith(MANIFEST_PATH_SUFFIX)
    ):
        raise ValueError(MANIFEST_URL_ERROR)

    base_path = parsed.path[: -len(MANIFEST_PATH_SUFFIX)]
    segments = [segment for segment in base_path.split("/") if segment]
    if len(segments) < 3:
        raise ValueError(MANIFEST_URL_ERROR)
    return f"https://raw.githubusercontent.com/{'/'.join(segments)}/"


def relative_path(path: Path, repo_root: Path) -> str:
    return path.resolve().relative_to(repo_root.resolve()).as_posix()


def display_path(path: Path, repo_root: Path) -> str:
    try:
        return relative_path(path, repo_root)
    except ValueError:
        return path.resolve().as_posix()


def slugify(value: str) -> str:
    slug = re.sub(r"[^a-z0-9]+", "-", value.lower()).strip("-")
    return slug or "automation"


def write_manifest(manifest: dict[str, Any], output_path: Path) -> None:
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Generate the Pavbot public manifest.")
    parser.add_argument(
        "--repo-root",
        default=Path(__file__).resolve().parents[1],
        type=Path,
        help="Repository root to scan.",
    )
    parser.add_argument(
        "--output",
        default=Path("public/pavbot-manifest.json"),
        type=Path,
        help="Manifest JSON output path.",
    )
    parser.add_argument(
        "--raw-base-url",
        default=os.environ.get("PAVBOT_RAW_BASE_URL", ""),
        help="Base public raw URL for repo files.",
    )
    parser.add_argument(
        "--manifest-url",
        default=os.environ.get("PAVBOT_MANIFEST_URL", ""),
        help=(
            "Public GitHub raw URL for public/pavbot-manifest.json. "
            "Used to derive --raw-base-url when --raw-base-url is not set."
        ),
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    repo_root = args.repo_root.resolve()
    output_path = args.output
    if not output_path.is_absolute():
        output_path = repo_root / output_path
    try:
        raw_base_url = resolve_raw_base_url(args.raw_base_url, args.manifest_url)
    except ValueError as exc:
        raise SystemExit(f"error: {exc}") from exc

    manifest = build_manifest(repo_root, raw_base_url=raw_base_url)
    write_manifest(manifest, output_path)
    print(f"manifest written: {display_path(output_path, repo_root)}")


if __name__ == "__main__":
    main()
