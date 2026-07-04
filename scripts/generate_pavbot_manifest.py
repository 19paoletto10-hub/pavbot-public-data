#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import urllib.parse
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

DATE_RE = re.compile(r"(?P<date>\d{4}-\d{2}-\d{2})(?:-(?P<time>\d{4}))?")
DOC_FIELD_RE = re.compile(r"^- (?P<key>Name|ID|Kind|Topic|Cadence|Output): `?(?P<value>.+?)`?$")
MANIFEST_URL_ERROR = (
    "PAVBOT_MANIFEST_URL must be a public GitHub raw manifest URL like "
    "https://raw.githubusercontent.com/<owner>/<repo>/<branch>/public/pavbot-manifest.json"
)
MANIFEST_PATH_SUFFIX = "/public/pavbot-manifest.json"
SCHEMA_VERSION_LEGACY = 1
SCHEMA_VERSION_LAYERS = 2
MANIFEST_MODE_FULL = "full"
MANIFEST_MODE_SHARDED = "sharded"
MANIFEST_FULL_PATH = "public/pavbot-manifest-full.json"
MANIFEST_TOPICS_DIR = "public/pavbot-topics"
MANIFEST_DELTAS_DIR = "public/pavbot-deltas"
DEFAULT_TOPIC_PAGE_SIZE = 50
DEFAULT_DELTA_HISTORY = 30
MOBILE_PUBLIC_ONLY_TOPIC = "aktualne-wydarzenia-mobile"
LLM_JOBS_TOPIC = "llm-ai-jobs-wroclaw"
PULSE_NEWS_TOPIC = "puls-dnia-news"
REDDIT_RADAR_TOPIC = "reddit-radar"
RESEARCH_DATA_TOPICS = {"tech-news", "polska-swiat"}
APP_VISIBLE_PODCAST_FILES = {"podcast.mp3", "brief.pdf", "script.md"}


def _iso_timestamp() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def canonical_json(payload: Any) -> str:
    return json.dumps(payload, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def compute_payload_hash(payload: Any) -> str:
    return hashlib.sha1(canonical_json(payload).encode("utf-8")).hexdigest()


def artifact_sort_key(artifact: dict[str, Any]) -> tuple[str, str, str, str, str]:
    topic = str(artifact.get("topic") or "")
    date = str(artifact.get("date") or "")
    time = str(artifact.get("time") or "")
    updated_at = f"{date}T{time}" if time else date
    artifact_id = str(artifact.get("id") or "")
    return (topic, updated_at, artifact_id, str(artifact.get("path") or ""), str(artifact.get("title") or ""))


def previous_manifest_revision(manifest: dict[str, Any] | None) -> int:
    if isinstance(manifest, dict):
        return int(manifest.get("revision", 0) or 0)
    return 0


def next_revision(previous: int) -> int:
    now = int(datetime.now(timezone.utc).timestamp())
    if previous <= 0:
        return max(1, now)
    if previous >= now:
        return previous + 1
    return now


def normalize_manifest_payload(payload: dict[str, Any], keep_generated_at: bool = True) -> dict[str, Any]:
    normalized = dict(payload)
    if keep_generated_at:
        normalized.pop("payloadHash", None)
    return normalized


def build_manifest(repo_root: Path, raw_base_url: str = "", public_feed: bool = True) -> dict[str, Any]:
    repo_root = repo_root.resolve()
    raw_base_url = normalize_base_url(raw_base_url)
    topics = collect_topics(repo_root, raw_base_url, public_feed=public_feed)
    return {
        "schemaVersion": 1,
        "title": "Pavbot Automation Manifest",
        "generatedAt": datetime.now(timezone.utc).isoformat(),
        "rawBaseUrl": raw_base_url,
        "automations": collect_automations(repo_root, raw_base_url, public_feed=public_feed),
        "topics": topics,
        "artifacts": collect_artifacts(repo_root, raw_base_url, topics, public_feed=public_feed),
    }


def collect_artifacts_by_topic(artifacts: list[dict[str, Any]]) -> dict[str, list[dict[str, Any]]]:
    grouped: dict[str, list[dict[str, Any]]] = {}
    for item in artifacts:
        topic = item.get("topic")
        if not topic:
            continue
        grouped.setdefault(str(topic), []).append(item)

    for topic_items in grouped.values():
        topic_items.sort(
            key=lambda item: (
                item.get("date") or "",
                item.get("time") or "",
                item.get("path") or "",
                item.get("id") or "",
            ),
            reverse=True,
        )

    return grouped


def build_topic_manifest_payload(
    *,
    topic: dict[str, Any],
    artifacts: list[dict[str, Any]],
    topic_manifest_url: str,
    topic_manifest_path: str,
    topic_page_size: int,
) -> dict[str, Any]:
    topic_slug = str(topic.get("slug") or "")
    page_size = max(1, topic_page_size)
    topic_items = list(artifacts)
    topic_items.sort(
        key=lambda item: (
            item.get("date") or "",
            item.get("time") or "",
            item.get("path") or "",
            item.get("id") or "",
        ),
        reverse=True,
    )

    latest = topic_items[0] if topic_items else None
    page_items = topic_items[:page_size]
    return {
        "schemaVersion": 1,
        "generatedAt": datetime.now(timezone.utc).isoformat(),
        "slug": topic_slug,
        "title": topic.get("title") or topic_slug,
        "path": topic.get("path") or f"research/{topic_slug}",
        "topicFilePath": topic.get("topicFilePath") or "",
        "url": topic.get("url") or "",
        "artifactCount": len(topic_items),
        "pageSize": page_size,
        "nextPageToken": str(page_size) if len(topic_items) > page_size else None,
        "pageEtag": compute_payload_hash(page_items),
        "items": page_items,
        "latestArtifactId": latest.get("id") if latest else None,
        "lastUpdated": latest.get("date") if latest else None,
        "topicManifestUrl": topic_manifest_url,
        "topicManifestPath": topic_manifest_path,
    }


def compute_payload_hash(payload: Any) -> str:
    return hashlib.sha1(json.dumps(payload, ensure_ascii=False, sort_keys=True).encode("utf-8")).hexdigest()


def compute_manifest_delta(
    previous_full_manifest: dict[str, Any],
    current_full_manifest: dict[str, Any],
    previous_revision: int,
    current_revision: int,
) -> dict[str, list[dict[str, Any]]]:
    previous_artifacts = {
        str(item.get("id")): item
        for item in previous_full_manifest.get("artifacts", [])
        if isinstance(item, dict) and item.get("id")
    }
    current_artifacts = {
        str(item.get("id")): item
        for item in current_full_manifest.get("artifacts", [])
        if isinstance(item, dict) and item.get("id")
    }
    previous_automations = {
        str(item.get("id")): item
        for item in previous_full_manifest.get("automations", [])
        if isinstance(item, dict) and item.get("id")
    }
    current_automations = {
        str(item.get("id")): item
        for item in current_full_manifest.get("automations", [])
        if isinstance(item, dict) and item.get("id")
    }

    artifact_changes: list[dict[str, Any]] = []
    for artifact_id in sorted(current_artifacts):
        if artifact_id not in previous_artifacts:
            artifact_changes.append(
                {
                    "action": "add",
                    "artifactId": artifact_id,
                    "artifact": current_artifacts[artifact_id],
                    "updatedAt": datetime.now(timezone.utc).isoformat(),
                    "fromRevision": previous_revision,
                    "toRevision": current_revision,
                }
            )

    for artifact_id in sorted(previous_artifacts):
        if artifact_id not in current_artifacts:
            artifact_changes.append(
                {
                    "action": "remove",
                    "artifactId": artifact_id,
                    "updatedAt": datetime.now(timezone.utc).isoformat(),
                    "fromRevision": previous_revision,
                    "toRevision": current_revision,
                }
            )

    automation_changes: list[dict[str, Any]] = []
    for automation_id in sorted(current_automations):
        if automation_id not in previous_automations:
            automation_changes.append(
                {
                    "action": "add",
                    "automationId": automation_id,
                    "automation": current_automations[automation_id],
                    "updatedAt": datetime.now(timezone.utc).isoformat(),
                    "fromRevision": previous_revision,
                    "toRevision": current_revision,
                }
            )

    for automation_id in sorted(previous_automations):
        if automation_id not in current_automations:
            automation_changes.append(
                {
                    "action": "remove",
                    "automationId": automation_id,
                    "updatedAt": datetime.now(timezone.utc).isoformat(),
                    "fromRevision": previous_revision,
                    "toRevision": current_revision,
                }
            )

    return {"artifacts": artifact_changes, "automations": automation_changes}


def _manifest_semantic_payload(payload: dict[str, Any] | None) -> dict[str, Any]:
    if not isinstance(payload, dict):
        return {}
    snapshot = dict(payload)
    snapshot.pop("generatedAt", None)
    snapshot.pop("previousRevision", None)
    return snapshot


def to_int_revision(value: Any) -> int | None:
    if isinstance(value, int):
        return value
    if isinstance(value, str) and value.isdigit():
        return int(value)
    return None


def write_manifest_with_revision(path: Path, payload: dict[str, Any], *, preserve_generated_at: bool) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    existing_text: str | None = None
    existing_payload: dict[str, Any] | None = None

    if path.exists():
        existing_text = path.read_text(encoding="utf-8")
        try:
            loaded = json.loads(existing_text)
        except (json.JSONDecodeError, UnicodeDecodeError):
            loaded = None
        if isinstance(loaded, dict):
            existing_payload = loaded

    if preserve_generated_at and existing_payload is not None and _manifest_semantic_payload(existing_payload) == _manifest_semantic_payload(
        payload
    ):
        existing_generated_at = existing_payload.get("generatedAt")
        if isinstance(existing_generated_at, str) and existing_generated_at.strip():
            payload["generatedAt"] = existing_generated_at

    rendered = json.dumps(payload, ensure_ascii=False, indent=2) + "\n"
    if existing_text == rendered:
        return
    path.write_text(rendered, encoding="utf-8")


def write_sharded_manifest_files(
    *,
    full_manifest: dict[str, Any],
    catalog_manifest: dict[str, Any],
    topic_manifests: dict[str, dict[str, Any]],
    output_path: Path,
    delta_manifest: dict[str, Any] | None,
) -> None:
    output_root = output_path.parent
    full_output_path = output_root / MANIFEST_FULL_PATH
    topics_output_dir = output_root / MANIFEST_TOPICS_DIR
    deltas_output_dir = output_root / MANIFEST_DELTAS_DIR

    write_manifest(full_manifest, full_output_path)
    write_manifest_with_revision(output_path, catalog_manifest, preserve_generated_at=True)

    for topic_slug, topic_payload in topic_manifests.items():
        write_manifest_with_revision(
            topics_output_dir / f"{topic_slug}.json",
            topic_payload,
            preserve_generated_at=True,
        )

    if delta_manifest is None:
        return

    from_revision = to_int_revision(delta_manifest.get("fromRevision"))
    to_revision = to_int_revision(delta_manifest.get("toRevision"))
    if from_revision is None or to_revision is None:
        return

    delta_path = deltas_output_dir / f"{from_revision}-{to_revision}.json"
    write_manifest_with_revision(delta_path, delta_manifest, preserve_generated_at=False)


def build_manifest_catalog(
    repo_root: Path,
    full_manifest: dict[str, Any],
    raw_base_url: str,
    topic_page_size: int,
    previous_manifest: dict[str, Any] | None,
) -> tuple[dict[str, Any], dict[str, dict[str, Any]], dict[str, Any] | None]:
    topics = full_manifest.get("topics", [])
    artifacts = [item for item in full_manifest.get("artifacts", []) if isinstance(item, dict)]
    artifacts_by_topic = collect_artifacts_by_topic(artifacts)

    catalog_topics: list[dict[str, Any]] = []
    topic_manifests: dict[str, dict[str, Any]] = {}

    for topic in sorted(topics, key=lambda item: str(item.get("slug") or "")):
        topic_slug = str(topic.get("slug") or "")
        topic_artifacts = artifacts_by_topic.get(topic_slug, [])
        topic_manifest_path = f"{MANIFEST_TOPICS_DIR}/{topic_slug}.json"
        topic_manifest_url = f"{normalize_base_url(raw_base_url)}{topic_manifest_path}"

        topic_payload = build_topic_manifest_payload(
            topic=topic,
            artifacts=topic_artifacts,
            topic_manifest_url=topic_manifest_url,
            topic_manifest_path=topic_manifest_path,
            topic_page_size=topic_page_size,
        )
        catalog_topics.append(
            {
                "id": f"topic-{topic_slug}",
                "slug": topic_slug,
                "title": topic.get("title") or topic_slug,
                "artifactCount": len(topic_artifacts),
                "lastUpdated": topic_artifacts[0].get("date") if topic_artifacts else None,
                "latestArtifactId": topic_artifacts[0].get("id") if topic_artifacts else None,
                "topicManifestUrl": topic_manifest_url,
                "topicManifestPath": topic_manifest_path,
                "topicManifestEtag": topic_payload.get("pageEtag"),
            }
        )
        topic_manifests[topic_slug] = topic_payload

    catalog_payload = {
        "schemaVersion": 1,
        "title": full_manifest.get("title") or "Pavbot Automation Manifest",
        "generatedAt": full_manifest.get("generatedAt") or datetime.now(timezone.utc).isoformat(),
        "rawBaseUrl": raw_base_url,
        "revision": 1,
        "topics": catalog_topics,
        "automations": full_manifest.get("automations", []),
        "artifacts": [],
        "fullManifestUrl": f"{normalize_base_url(raw_base_url)}{MANIFEST_FULL_PATH}",
        "topicManifestsUrl": f"{normalize_base_url(raw_base_url)}{MANIFEST_TOPICS_DIR}/",
        "topicManifestsBaseUrl": f"{normalize_base_url(raw_base_url)}{MANIFEST_TOPICS_DIR}/",
        "deltasUrl": f"{normalize_base_url(raw_base_url)}{MANIFEST_DELTAS_DIR}/",
    }

    delta_payload = None
    previous_revision = to_int_revision(previous_manifest.get("revision") if isinstance(previous_manifest, dict) else None)
    if previous_revision is None:
        previous_revision = 0

    candidate_without_revision = dict(catalog_payload)
    candidate_without_revision.pop("revision", None)
    previous_without_revision = None
    if isinstance(previous_manifest, dict):
        previous_without_revision = dict(previous_manifest)
        previous_without_revision.pop("revision", None)

    catalog_changed = True
    if previous_without_revision is not None:
        catalog_changed = _manifest_semantic_payload(candidate_without_revision) != _manifest_semantic_payload(
            previous_without_revision
        )

    if catalog_changed:
        new_revision = previous_revision + 1
        catalog_payload["revision"] = new_revision
        catalog_payload["previousRevision"] = previous_revision if previous_revision else None
        if previous_revision:
            changes = compute_manifest_delta(previous_manifest or {}, full_manifest, previous_revision, new_revision)
            if changes["artifacts"] or changes["automations"]:
                delta_file = f"{previous_revision}-{new_revision}.json"
                catalog_payload["recentManifestChanges"] = {
                    "fromRevision": previous_revision,
                    "toRevision": new_revision,
                    "deltaUrl": f"{normalize_base_url(raw_base_url)}{MANIFEST_DELTAS_DIR}/{delta_file}",
                }
                delta_payload = {
                    "schemaVersion": 1,
                    "fromRevision": previous_revision,
                    "toRevision": new_revision,
                    "generatedAt": catalog_payload["generatedAt"],
                    "artifactChanges": changes["artifacts"],
                    "automationChanges": changes["automations"],
                }
    else:
        catalog_payload["revision"] = previous_revision if previous_revision else 1
        catalog_payload["previousRevision"] = previous_revision if previous_revision else None

    return catalog_payload, topic_manifests, delta_payload


def manifest_semantic_payload(manifest: dict[str, Any]) -> dict[str, Any]:
    payload = dict(manifest)
    payload.pop("generatedAt", None)
    return payload


def collect_automations(repo_root: Path, raw_base_url: str, public_feed: bool) -> list[dict[str, Any]]:
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
            "sourcePath": "" if public_feed else "docs/how-to-use.md",
            "sourceUrl": "" if public_feed else raw_url(raw_base_url, "docs/how-to-use.md"),
        }
        if output:
            entry["output"] = output
            if not public_feed:
                entry["outputUrl"] = raw_url(raw_base_url, output)
        result.append(entry)

    return sorted(result, key=lambda item: (item["topic"], item["kind"], item["name"]))


def collect_topics(repo_root: Path, raw_base_url: str, public_feed: bool) -> list[dict[str, Any]]:
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
                "topicFilePath": "" if public_feed else rel_path,
                "url": "" if public_feed else raw_url(raw_base_url, rel_path),
            }
        )

    return topics


def has_topic_artifact_fallback(topic_dir: Path) -> bool:
    if topic_dir.name == PULSE_NEWS_TOPIC:
        return any((topic_dir / "data").glob("*-pulse-news.json"))
    if topic_dir.name == MOBILE_PUBLIC_ONLY_TOPIC:
        return any((topic_dir / "data").glob("*-mobile-news.json"))
    if topic_dir.name == LLM_JOBS_TOPIC:
        return any((topic_dir / "data").glob("*-jobs.json")) or any((topic_dir / "runs").glob("*.md"))
    if topic_dir.name == REDDIT_RADAR_TOPIC:
        return any((topic_dir / "data").glob("*-reddit-radar.json")) or any(
            (topic_dir / "runs").glob("*-reddit-radar.md")
        )
    if topic_dir.name in RESEARCH_DATA_TOPICS:
        return any((topic_dir / "data").glob("*-research.json")) or any((topic_dir / "runs").glob("*.md"))
    return False


def fallback_topic_title(slug: str) -> str:
    if slug == PULSE_NEWS_TOPIC:
        return "Pavbot Puls Dnia News"
    if slug == MOBILE_PUBLIC_ONLY_TOPIC:
        return "Pavbot Aktualne Wydarzenia Mobile"
    if slug == LLM_JOBS_TOPIC:
        return "Pavbot LLM/AI Jobs Wrocław"
    if slug == REDDIT_RADAR_TOPIC:
        return "Pavbot Reddit Radar"
    if slug == "tech-news":
        return "Pavbot Tech News"
    if slug == "polska-swiat":
        return "Pavbot Polska Świat"
    return slug


def collect_artifacts(
    repo_root: Path,
    raw_base_url: str,
    topics: list[dict[str, Any]],
    public_feed: bool,
) -> list[dict[str, Any]]:
    artifacts: list[dict[str, Any]] = []
    for topic in topics:
        topic_dir = repo_root / topic["path"]
        slug = topic["slug"]

        if slug == MOBILE_PUBLIC_ONLY_TOPIC:
            collect_mobile_public_artifacts(artifacts, repo_root, raw_base_url, topic_dir, slug)
            continue

        if not public_feed:
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
        elif slug == REDDIT_RADAR_TOPIC:
            for path in sorted((topic_dir / "data").glob("*-reddit-radar.json")):
                add_artifact(artifacts, repo_root, raw_base_url, path, slug, "redditRadarData")
            for path in sorted((topic_dir / "data").glob("*-reddit-radar-raw.json")):
                add_artifact(artifacts, repo_root, raw_base_url, path, slug, "redditRadarRawData")
        elif slug in RESEARCH_DATA_TOPICS:
            for path in sorted((topic_dir / "data").glob("*.json")):
                add_artifact(artifacts, repo_root, raw_base_url, path, slug, "researchData")

        if not public_feed:
            for path in sorted((topic_dir / "proposals").glob("*.md")):
                add_artifact(artifacts, repo_root, raw_base_url, path, slug, "proposal")

        podcasts_dir = topic_dir / "podcasts"
        if podcasts_dir.exists():
            for date_dir in sorted(path for path in podcasts_dir.iterdir() if path.is_dir()):
                for path in sorted(item for item in date_dir.rglob("*") if item.is_file()):
                    if not is_manifest_podcast_artifact(path, public_feed=public_feed):
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

    for path in sorted((topic_dir / "pdfs").glob("*-newspaper.pdf")):
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
    if is_finder_style_duplicate(path):
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
    if artifact_type == "pulseNewsData":
        item_count = pulse_news_item_count(path)
        if item_count is not None:
            artifact["itemCount"] = item_count
    artifacts.append(artifact)


def is_finder_style_duplicate(path: Path) -> bool:
    return re.search(r" \d+$", path.stem) is not None


def pulse_news_item_count(path: Path) -> int | None:
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError, UnicodeDecodeError):
        return None
    items = payload.get("items") if isinstance(payload, dict) else None
    return len(items) if isinstance(items, list) else None


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


def is_manifest_podcast_artifact(path: Path, public_feed: bool) -> bool:
    if public_feed:
        return path.name in APP_VISIBLE_PODCAST_FILES
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
    if artifact_type == "redditRadarData":
        return "Reddit Radar data"
    if artifact_type == "redditRadarRawData":
        return "Reddit Radar raw data"
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
    existing_text: str | None = None
    existing_manifest: dict[str, Any] | None = None
    if output_path.exists():
        existing_text = output_path.read_text(encoding="utf-8")
        try:
            payload = json.loads(existing_text)
        except (json.JSONDecodeError, UnicodeDecodeError):
            payload = None
        if isinstance(payload, dict):
            existing_manifest = payload

    if existing_manifest and manifest_semantic_payload(existing_manifest) == manifest_semantic_payload(manifest):
        existing_generated_at = existing_manifest.get("generatedAt")
        if isinstance(existing_generated_at, str) and existing_generated_at.strip():
            manifest["generatedAt"] = existing_generated_at

    rendered_manifest = json.dumps(manifest, ensure_ascii=False, indent=2) + "\n"
    if existing_text == rendered_manifest:
        return
    output_path.write_text(rendered_manifest, encoding="utf-8")


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
    parser.add_argument(
        "--include-developer-artifacts",
        action="store_true",
        help="Include prompts, topic files, backlogs, proposals, and podcast process metadata.",
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

    manifest = build_manifest(
        repo_root,
        raw_base_url=raw_base_url,
        public_feed=not args.include_developer_artifacts,
    )
    write_manifest(manifest, output_path)
    print(f"manifest written: {display_path(output_path, repo_root)}")


if __name__ == "__main__":
    main()
