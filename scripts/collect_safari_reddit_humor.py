#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import html
import json
import os
import re
import subprocess
import sys
import urllib.request
from copy import deepcopy
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any
from zoneinfo import ZoneInfo


DEFAULT_SUBREDDITS = (
    "Polska_wpz",
    "memes",
    "ProgrammerHumor",
    "Polska",
    "technology",
    "AskReddit",
    "mildlyinfuriating",
    "OutOfTheLoop",
    "facepalm",
)
DEFAULT_NOTIFIER_URL = "https://notify.paweltanski.com"
DEFAULT_SOURCE = "Codex Safari Reddit radar"
DEFAULT_ARTIFACT_ROOT = Path("research/reddit-radar")
DEFAULT_HISTORY_LOOKBACK_DAYS = 5
RAW_DETAIL_KEYS = {"rawCommentSnippets", "commentSnippets", "commentsList"}
COMMENT_ANALYSIS_SOURCE = "codex-computer-use-safari"
COMMENT_ANALYSIS_STATUSES = {"reviewed", "no_safe_comments", "blocked"}
COMMENT_ANALYSIS_KEYS = {"commentAnalysisStatus", "commentAnalysisSource", "commentAnalysisNote"}
COMMENT_ANALYSIS_REQUIRED_NOTE = (
    "Wymaga ręcznego przeglądu posta i komentarzy w Safari/Computer Use przed publikacją."
)
INTERNAL_DETAIL_KEYS = RAW_DETAIL_KEYS | COMMENT_ANALYSIS_KEYS | {"radarFirstSeenAt", "radarLastSeenAt", "radarKey"}


SAFARI_EXTRACT_JS = r"""
(() => {
  const parseCount = (value) => {
    if (!value) return 0;
    const text = String(value).toLowerCase().replace(/,/g, '').trim();
    const match = text.match(/([\d.]+)\s*([km])?/);
    if (!match) return 0;
    const base = Number(match[1]);
    if (!Number.isFinite(base)) return 0;
    if (match[2] === 'k') return Math.round(base * 1000);
    if (match[2] === 'm') return Math.round(base * 1000000);
    return Math.round(base);
  };

  const absolutize = (href) => {
    if (!href) return '';
    try {
      return new URL(href, 'https://www.reddit.com').toString();
    } catch (_) {
      return '';
    }
  };

  const fromShredditPost = [...document.querySelectorAll('shreddit-post')].map((post) => {
    const permalink = post.getAttribute('permalink') || post.querySelector('a[href*="/comments/"]')?.getAttribute('href') || '';
    const title =
      post.getAttribute('post-title') ||
      post.querySelector('[slot="title"]')?.textContent ||
      post.querySelector('a[href*="/comments/"]')?.textContent ||
      '';
    const image =
      post.getAttribute('content-href') ||
      post.querySelector('img[src]')?.getAttribute('src') ||
      null;
    return {
      title,
      url: absolutize(permalink),
      imageURL: image && /^https?:/.test(image) ? image : null,
      score: parseCount(post.getAttribute('score') || post.querySelector('[id*="vote-arrows"]')?.textContent),
      comments: parseCount(post.getAttribute('comment-count') || post.querySelector('a[href*="/comments/"]')?.textContent),
      over18: post.hasAttribute('nsfw') || post.getAttribute('over-18') === 'true'
    };
  });

  const fromLinks = [...document.querySelectorAll('a[href*="/comments/"]')].map((anchor) => {
    const title = anchor.textContent || anchor.getAttribute('aria-label') || '';
    const card = anchor.closest('article, faceplate-tracker, div');
    const image = card?.querySelector?.('img[src]')?.getAttribute('src') || null;
    return {
      title,
      url: absolutize(anchor.getAttribute('href')),
      imageURL: image && /^https?:/.test(image) ? image : null,
      score: parseCount(card?.textContent),
      comments: 0,
      over18: /nsfw|18\+|adult/i.test(card?.textContent || '')
    };
  });

  const posts = fromShredditPost.length ? fromShredditPost : fromLinks;
  return JSON.stringify(posts.slice(0, 24));
})()
"""


SAFARI_POST_DETAIL_JS = r"""
(() => {
  const parseCount = (value) => {
    if (!value) return 0;
    const text = String(value).toLowerCase().replace(/,/g, '').trim();
    const match = text.match(/([\d.]+)\s*([km])?/);
    if (!match) return 0;
    const base = Number(match[1]);
    if (!Number.isFinite(base)) return 0;
    if (match[2] === 'k') return Math.round(base * 1000);
    if (match[2] === 'm') return Math.round(base * 1000000);
    return Math.round(base);
  };

  const clean = (value) => String(value || '').replace(/\s+/g, ' ').trim();
  const postText = clean(
    document.querySelector('shreddit-post [slot="text-body"]')?.innerText ||
    document.querySelector('[slot="text-body"]')?.innerText ||
    document.querySelector('[data-post-click-location="text-body"]')?.innerText ||
    ''
  );

  const comments = [...document.querySelectorAll('shreddit-comment')].map((comment) => {
    const body = clean(
      comment.querySelector('[slot="comment"]')?.innerText ||
      comment.querySelector('[id*="comment-rtjson-content"]')?.innerText ||
      comment.textContent ||
      ''
    );
    return {
      body,
      score: parseCount(comment.getAttribute('score') || comment.textContent)
    };
  }).filter((comment) => comment.body && comment.body.length >= 12).slice(0, 8);

  return JSON.stringify({postText, commentSnippets: comments});
})()
"""


def load_env_file(path: Path) -> None:
    if not path.exists():
        return
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip().strip('"').strip("'")
        if key and key not in os.environ:
            os.environ[key] = value


def stable_id(value: str) -> str:
    digest = hashlib.sha1(value.encode("utf-8")).hexdigest()[:10]
    cleaned = re.sub(r"[^a-zA-Z0-9]+", "-", value.lower()).strip("-")[:48]
    return f"{cleaned or 'reddit'}-{digest}"


def clean_text(value: Any) -> str:
    return re.sub(r"\s+", " ", str(value or "")).strip()


def shorten_text(value: Any, limit: int) -> str:
    text = clean_text(value)
    if len(text) <= limit:
        return text
    return text[: max(0, limit - 1)].rstrip() + "…"


def parse_int(value: Any) -> int:
    if isinstance(value, int):
        return value
    if isinstance(value, float):
        return int(value)
    text = clean_text(value).lower().replace(",", "")
    match = re.search(r"([\d.]+)\s*([km])?", text)
    if not match:
        return 0
    number = float(match.group(1))
    suffix = match.group(2)
    if suffix == "k":
        number *= 1_000
    elif suffix == "m":
        number *= 1_000_000
    return int(number)


def normalize_reddit_url(value: Any) -> str:
    text = clean_text(value)
    if not text:
        return ""
    if text.startswith("/"):
        return f"https://www.reddit.com{text}"
    if text.startswith("https://reddit.com/"):
        return text.replace("https://reddit.com/", "https://www.reddit.com/", 1)
    if text.startswith("https://www.reddit.com/"):
        return text
    return ""


def looks_toxic(title: str) -> bool:
    lowered = title.lower()
    blocked = ("nsfw", "porn", "gore", "kill yourself")
    return any(token in lowered for token in blocked)


def looks_deleted_or_empty(value: str) -> bool:
    lowered = clean_text(value).lower()
    return lowered in {"[deleted]", "[removed]", "deleted", "removed"} or not lowered


def caption_for_title(title: str) -> str:
    lowered = title.lower()
    if any(token in lowered for token in ("ai", "chatgpt", "llm")):
        return "AI robi swoje, ludzie robią screeny, internet robi resztę."
    if any(token in lowered for token in ("deploy", "bug", "code", "programmer")):
        return "Ten typ humoru zna każdy, kto choć raz czekał na zielone CI."
    if any(token in lowered for token in ("polska", "rząd", "sejm", "prezydent")):
        return "Sygnał społecznościowy z Reddita; komentarze są kontekstem, nie źródłem faktów."
    return "Krótki sygnał społecznościowy, dobry do szybkiego przewinięcia."


def category_label_for(tags: list[str], source_name: str) -> str:
    values: list[str] = []
    for tag in tags:
        normalized = clean_text(tag)
        if not normalized or normalized.lower() == "trend":
            continue
        if normalized not in values:
            values.append(normalized)
    if len(values) > 1:
        values = [value for value in values if value.lower() != "memy"] or values
    if not values:
        source = source_name.removeprefix("r/")
        values.append(source or "trend")
    return ", ".join(values[:3])


def why_funny_for(title: str, category_label: str) -> str:
    lowered = f"{title} {category_label}".lower()
    if "ai" in lowered or "chatgpt" in lowered or "llm" in lowered:
        return "Zabawne, bo AI występuje tu jak zbyt pewny siebie uczestnik codziennego rytuału, a ludzie dopisują puentę."
    if "dev" in lowered or "programmer" in lowered or "deploy" in lowered or "code" in lowered:
        return "Zabawne, bo przerabia znany stres techniczny na małą scenkę z pracy."
    if "pl" in lowered or "polska" in lowered:
        return "Zabawne, bo lokalny internet bierze zwykły temat i robi z niego wspólny rytuał komentowania."
    return "Zabawne, bo temat jest prosty, rozpoznawalny i zostawia miejsce na szybkie puenty w komentarzach."


def comment_explanation_for(comment: str, title: str, category_label: str) -> str:
    lowered = f"{comment} {title} {category_label}".lower()
    if "ai" in lowered or "chatgpt" in lowered or "llm" in lowered:
        return "Komentarz jest ciekawy, bo rozwija żart o AI i pokazuje, jak ludzie dopisują puentę do technologicznego absurdu."
    if "deploy" in lowered or "ci" in lowered or "bug" in lowered or "code" in lowered or "programmer" in lowered:
        return "Komentarz jest ciekawy, bo rozwija techniczny żart i trafia w znany rytuał sprawdzania, czy sukces nie ukrywa awarii."
    if "polska" in lowered or "wpz" in lowered or "pl" in lowered:
        return "Komentarz jest ciekawy, bo pokazuje lokalny kontekst i zamienia zwykły temat w wspólną, rozpoznawalną puentę."
    return "Komentarz jest ciekawy, bo dopowiada codzienny absurd z wątku i zamienia go w krótką puentę."


GENERIC_COMMENT_EXPLANATIONS = {
    "Komentarz jest ciekawy, bo rozwija żart o AI i pokazuje, jak ludzie dopisują puentę do technologicznego absurdu.",
    "Komentarz jest ciekawy, bo rozwija techniczny żart i trafia w znany rytuał sprawdzania, czy sukces nie ukrywa awarii.",
    "Komentarz jest ciekawy, bo pokazuje lokalny kontekst i zamienia zwykły temat w wspólną, rozpoznawalną puentę.",
    "Komentarz jest ciekawy, bo dopowiada codzienny absurd z wątku i zamienia go w krótką puentę.",
}


def tags_for(title: str, source_name: str) -> list[str]:
    corpus = f"{title} {source_name}".lower()
    tags: list[str] = []
    if any(token in corpus for token in ("polska", "wpz", "rząd", "sejm")):
        tags.append("PL")
    if any(token in corpus for token in ("meme", "mem", "humor")):
        tags.append("memy")
    if any(token in corpus for token in ("ai", "chatgpt", "llm", "openai")):
        tags.append("AI")
    if any(token in corpus for token in ("programmer", "code", "bug", "deploy", "dev")):
        tags.append("dev")
    return tags[:3] or ["trend"]


def comment_highlights_from(value: Any, *, title: str = "", category_label: str = "") -> list[dict[str, Any]]:
    if not isinstance(value, list):
        return []
    candidates: list[dict[str, Any]] = []
    seen: set[str] = set()
    for raw in value:
        if isinstance(raw, dict):
            body = clean_text(raw.get("body") or raw.get("summary") or raw.get("text"))
            score = parse_int(raw.get("score"))
        else:
            body = clean_text(raw)
            score = 0
        key = body.lower()
        if not body or key in seen or looks_deleted_or_empty(body) or looks_toxic(body):
            continue
        seen.add(key)
        candidates.append({"body": body, "score": score})
    candidates.sort(key=lambda item: (parse_int(item.get("score")), len(clean_text(item.get("body")))), reverse=True)
    highlights: list[dict[str, Any]] = []
    for candidate in candidates[:3]:
        body = clean_text(candidate.get("body"))
        highlights.append(
            {
                "id": f"comment-{len(highlights) + 1}",
                "summary": shorten_text(body, 180),
                "originalBody": body,
                "explanation": comment_explanation_for(body, title, category_label),
                "score": parse_int(candidate.get("score")),
            }
        )
    return highlights


def curate_posts(posts: list[dict[str, Any]], *, max_items: int) -> list[dict[str, Any]]:
    curated: list[dict[str, Any]] = []
    seen: set[str] = set()
    for post in sorted(posts, key=lambda item: (parse_int(item.get("score")), parse_int(item.get("comments"))), reverse=True):
        title = clean_text(post.get("title"))
        source_url = normalize_reddit_url(post.get("sourceURL") or post.get("url"))
        if not title or not source_url or post.get("over18") or looks_toxic(title):
            continue
        key = title.lower()
        if key in seen:
            continue
        seen.add(key)
        source_name = clean_text(post.get("sourceName")) or source_name_from_url(source_url)
        tags = tags_for(title, source_name)
        category_label = category_label_for(tags, source_name)
        raw_comments = post.get("rawCommentSnippets") or post.get("commentSnippets") or post.get("commentsList") or []
        curated.append(
            {
                "id": stable_id(source_url or title),
                "title": title,
                "caption": caption_for_title(title),
                "sourceName": source_name,
                "sourceURL": source_url,
                "imageURL": post.get("imageURL") or None,
                "score": parse_int(post.get("score")),
                "comments": parse_int(post.get("comments")),
                "tags": tags,
                "categoryLabel": category_label,
                "postText": shorten_text(post.get("postText") or post.get("selfText"), 600) or None,
                "whyFunny": why_funny_for(title, category_label),
                "rawCommentSnippets": raw_comments if isinstance(raw_comments, list) else [],
                "commentHighlights": comment_highlights_from(raw_comments, title=title, category_label=category_label),
                "commentAnalysisStatus": "blocked",
                "commentAnalysisSource": "",
                "commentAnalysisNote": COMMENT_ANALYSIS_REQUIRED_NOTE,
            }
        )
        if len(curated) >= max_items:
            break
    return curated


def source_name_from_url(url: str) -> str:
    match = re.search(r"reddit\.com/r/([^/]+)", url)
    return f"r/{match.group(1)}" if match else "Reddit"


def next_even_hour_slot(local_now: datetime, *, interval_hours: int) -> datetime:
    candidate = local_now.replace(minute=6, second=0, microsecond=0)
    while candidate <= local_now or candidate.hour % interval_hours != 0:
        candidate += timedelta(hours=1)
        candidate = candidate.replace(minute=6, second=0, microsecond=0)
    return candidate


def digest_summary(items: list[dict[str, Any]]) -> str:
    if not items:
        return "Kategorie: trend. Najmocniej wybija się: <u>kilka lekkich tematów</u>."
    categories: list[str] = []
    for item in items:
        label = clean_text(item.get("categoryLabel"))
        if not label:
            label = category_label_for(list(item.get("tags") or []), clean_text(item.get("sourceName")))
        for raw_part in label.split(","):
            part = clean_text(raw_part)
            if part and part not in categories:
                categories.append(part)
    top = html.escape(clean_text(items[0].get("title")) or "kilka lekkich tematów", quote=False)
    return f"Kategorie: {', '.join(categories[:5]) or 'trend'}. Najmocniej wybija się: <u>{top}</u>."


def build_digest(
    *,
    items: list[dict[str, Any]],
    generated_at: datetime,
    interval_hours: int,
    timezone_name: str,
) -> dict[str, Any]:
    if generated_at.tzinfo is None:
        generated_at = generated_at.replace(tzinfo=timezone.utc)
    zone = ZoneInfo(timezone_name)
    local_generated_at = generated_at.astimezone(zone)
    next_refresh = next_even_hour_slot(local_generated_at, interval_hours=interval_hours)
    return {
        "id": f"humor-{local_generated_at.strftime('%Y-%m-%d-%H%M')}",
        "title": "<RR> Reddit Radar",
        "summary": digest_summary(items),
        "generatedAt": generated_at.astimezone(timezone.utc).isoformat(),
        "displayTime": local_generated_at.strftime("%H:%M"),
        "nextRefreshAt": next_refresh.isoformat(),
        "refreshIntervalHours": interval_hours,
        "items": items,
        "source": DEFAULT_SOURCE,
    }


def public_digest_payload(digest: dict[str, Any]) -> dict[str, Any]:
    public_digest = deepcopy(digest)
    public_items: list[dict[str, Any]] = []
    for item in public_digest.get("items") or []:
        if not isinstance(item, dict):
            continue
        public_item = {key: value for key, value in item.items() if key not in INTERNAL_DETAIL_KEYS}
        public_items.append(public_item)
    public_digest["items"] = public_items
    return public_digest


def digest_with_comment_analysis_defaults(digest: dict[str, Any]) -> dict[str, Any]:
    raw_digest = deepcopy(digest)
    items = raw_digest.get("items") if isinstance(raw_digest.get("items"), list) else []
    for item in items:
        if not isinstance(item, dict):
            continue
        status = clean_text(item.get("commentAnalysisStatus"))
        if status not in COMMENT_ANALYSIS_STATUSES:
            item["commentAnalysisStatus"] = "blocked"
        if clean_text(item.get("commentAnalysisStatus")) == "blocked":
            item.setdefault("commentAnalysisSource", "")
            item["commentAnalysisNote"] = clean_text(item.get("commentAnalysisNote")) or COMMENT_ANALYSIS_REQUIRED_NOTE
    return raw_digest


def reddit_radar_raw_path_for(final_path: Path) -> Path:
    name = final_path.name
    if name.endswith("-reddit-radar.json"):
        return final_path.with_name(name.replace("-reddit-radar.json", "-reddit-radar-raw.json"))
    return final_path.with_name(final_path.stem + "-raw.json")


def reddit_radar_markdown_path_for(final_path: Path) -> Path:
    name = final_path.name
    if name.endswith("-reddit-radar.json"):
        return final_path.parent.parent / "runs" / name.replace("-reddit-radar.json", "-reddit-radar.md")
    return final_path.with_suffix(".md")


def load_matching_reddit_radar_raw_digest(final_path: Path) -> dict[str, Any]:
    raw_path = reddit_radar_raw_path_for(final_path)
    if not raw_path.exists():
        return {}
    payload = json.loads(raw_path.read_text(encoding="utf-8"))
    return payload if isinstance(payload, dict) else {}


def raw_items_by_key(raw_digest: dict[str, Any]) -> dict[str, dict[str, Any]]:
    items = raw_digest.get("items") if isinstance(raw_digest.get("items"), list) else []
    by_key: dict[str, dict[str, Any]] = {}
    for item in items:
        if not isinstance(item, dict):
            continue
        key = reddit_radar_item_key(item)
        if key:
            by_key[key] = item
    return by_key


def why_funny_is_generic(item: dict[str, Any]) -> bool:
    title = clean_text(item.get("title"))
    category_label = clean_text(item.get("categoryLabel"))
    return clean_text(item.get("whyFunny")) == why_funny_for(title, category_label)


def comment_explanation_is_generic(highlight: dict[str, Any], item: dict[str, Any]) -> bool:
    explanation = clean_text(highlight.get("explanation"))
    if explanation in GENERIC_COMMENT_EXPLANATIONS:
        return True
    summary = clean_text(highlight.get("summary"))
    title = clean_text(item.get("title"))
    category_label = clean_text(item.get("categoryLabel"))
    return explanation == comment_explanation_for(summary, title, category_label)


def validate_digest_comment_analysis_for_publish(
    digest: dict[str, Any],
    *,
    raw_digest: dict[str, Any],
    final_path: Path | None = None,
) -> None:
    items = digest.get("items") if isinstance(digest.get("items"), list) else []
    if not items:
        return

    errors: list[str] = []
    raw_lookup = raw_items_by_key(raw_digest)
    for index, item in enumerate(items, start=1):
        if not isinstance(item, dict):
            errors.append(f"item {index}: invalid item payload")
            continue
        key = reddit_radar_item_key(item)
        raw_item = raw_lookup.get(key)
        label = clean_text(item.get("title")) or key or f"item {index}"
        if raw_item is None:
            errors.append(f"{label}: missing raw comment analysis metadata")
            continue

        status = clean_text(raw_item.get("commentAnalysisStatus"))
        source = clean_text(raw_item.get("commentAnalysisSource"))
        note = clean_text(raw_item.get("commentAnalysisNote"))
        highlights = item.get("commentHighlights") if isinstance(item.get("commentHighlights"), list) else []
        if status not in {"reviewed", "no_safe_comments"}:
            errors.append(f"{label}: commentAnalysisStatus must be reviewed or no_safe_comments")
        if source != COMMENT_ANALYSIS_SOURCE:
            errors.append(f"{label}: commentAnalysisSource must be {COMMENT_ANALYSIS_SOURCE}")
        if not clean_text(item.get("whyFunny")):
            errors.append(f"{label}: whyFunny is required")
        elif why_funny_is_generic(item):
            errors.append(f"{label}: whyFunny still looks like generic collector text")
        if len(highlights) > 3:
            errors.append(f"{label}: commentHighlights must contain at most 3 items")

        if status == "no_safe_comments":
            if highlights:
                errors.append(f"{label}: no_safe_comments requires empty commentHighlights")
            if not note:
                errors.append(f"{label}: no_safe_comments requires commentAnalysisNote")
            continue

        if status == "reviewed":
            if not highlights:
                errors.append(f"{label}: reviewed posts require at least one analyzed comment")
            for highlight_index, highlight in enumerate(highlights, start=1):
                if not isinstance(highlight, dict):
                    errors.append(f"{label}: comment {highlight_index} is invalid")
                    continue
                if not clean_text(highlight.get("id")):
                    errors.append(f"{label}: comment {highlight_index} id is required")
                if not clean_text(highlight.get("summary")):
                    errors.append(f"{label}: comment {highlight_index} summary is required")
                if not clean_text(highlight.get("originalBody")):
                    errors.append(f"{label}: comment {highlight_index} originalBody is required")
                explanation = clean_text(highlight.get("explanation"))
                if not explanation:
                    errors.append(f"{label}: comment {highlight_index} explanation is required")
                elif comment_explanation_is_generic(highlight, item):
                    errors.append(f"{label}: comment {highlight_index} explanation still looks generic")

    if errors:
        prefix = "Reddit Radar comment analysis quality gate failed"
        if final_path is not None:
            prefix += f" for {final_path}"
        raise RuntimeError(prefix + ": " + "; ".join(errors))


def reddit_radar_item_key(item: dict[str, Any]) -> str:
    source_url = normalize_reddit_url(item.get("sourceURL") or item.get("url"))
    if source_url:
        return source_url.lower().rstrip("/")
    return clean_text(item.get("title")).lower()


def merge_reddit_radar_items(
    previous_items: list[dict[str, Any]],
    fresh_items: list[dict[str, Any]],
    *,
    max_items: int,
    replace_count: int,
    generated_at: datetime,
) -> list[dict[str, Any]]:
    now = generated_at.astimezone(timezone.utc).isoformat()
    max_items = max(1, min(max_items, 12))
    replace_count = max(1, min(replace_count, max_items))

    previous_by_key: dict[str, dict[str, Any]] = {}
    for item in previous_items:
        if not isinstance(item, dict):
            continue
        key = reddit_radar_item_key(item)
        if not key or key in previous_by_key:
            continue
        next_item = dict(item)
        next_item["radarKey"] = key
        next_item.setdefault("radarFirstSeenAt", now)
        next_item["radarLastSeenAt"] = now
        previous_by_key[key] = next_item

    additions: list[dict[str, Any]] = []
    seen_fresh: set[str] = set()
    for item in fresh_items:
        if not isinstance(item, dict):
            continue
        key = reddit_radar_item_key(item)
        if not key or key in previous_by_key or key in seen_fresh:
            continue
        seen_fresh.add(key)
        next_item = dict(item)
        next_item["radarKey"] = key
        next_item["radarFirstSeenAt"] = now
        next_item["radarLastSeenAt"] = now
        additions.append(next_item)

    previous = list(previous_by_key.values())
    if len(previous) < max_items:
        merged = previous + additions[: max_items - len(previous)]
    else:
        replacement_count = min(replace_count, len(additions))
        retained_count = max_items - replacement_count
        retained = sorted(
            previous,
            key=lambda item: clean_text(item.get("radarFirstSeenAt")),
            reverse=True,
        )[:retained_count]
        merged = retained + additions[:replacement_count]

    merged.sort(
        key=lambda item: (
            clean_text(item.get("radarFirstSeenAt")),
            parse_int(item.get("score")),
            parse_int(item.get("comments")),
        ),
        reverse=True,
    )
    return merged[:max_items]


def load_recent_reddit_radar_history_keys(
    output_root: Path,
    *,
    generated_at: datetime,
    lookback_days: int,
) -> set[str]:
    data_dir = output_root / "data"
    if lookback_days <= 0 or not data_dir.exists():
        return set()

    cutoff = generated_at.astimezone(timezone.utc) - timedelta(days=lookback_days)
    seen: set[str] = set()
    for path in sorted(data_dir.glob("*-reddit-radar.json")):
        stamp = path.name.removesuffix("-reddit-radar.json")
        try:
            stamp_dt = datetime.strptime(stamp, "%Y-%m-%d-%H%M").replace(tzinfo=ZoneInfo("Europe/Warsaw"))
        except ValueError:
            continue
        if stamp_dt.astimezone(timezone.utc) < cutoff:
            continue
        try:
            payload = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            continue
        items = payload.get("items") if isinstance(payload, dict) else None
        if not isinstance(items, list):
            continue
        for item in items:
            if not isinstance(item, dict):
                continue
            key = reddit_radar_item_key(item)
            if key:
                seen.add(key)
    return seen


def load_reddit_radar_state(output_root: Path) -> list[dict[str, Any]]:
    state_path = output_root / "data" / "reddit-radar-state.json"
    if not state_path.exists():
        return []
    try:
        payload = json.loads(state_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return []
    items = payload.get("items") if isinstance(payload, dict) else None
    return [item for item in items if isinstance(item, dict)] if isinstance(items, list) else []


def save_reddit_radar_state(output_root: Path, *, items: list[dict[str, Any]], generated_at: datetime) -> Path:
    state_path = output_root / "data" / "reddit-radar-state.json"
    state_path.parent.mkdir(parents=True, exist_ok=True)
    state = {
        "updatedAt": generated_at.astimezone(timezone.utc).isoformat(),
        "maxItems": 12,
        "replaceOldestCount": 6,
        "items": items,
    }
    state_path.write_text(json.dumps(state, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return state_path


def digest_stamp(digest: dict[str, Any], timezone_name: str = "Europe/Warsaw") -> str:
    generated_at = digest.get("generatedAt")
    try:
        parsed = datetime.fromisoformat(str(generated_at))
    except ValueError:
        parsed = datetime.now(timezone.utc)
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(ZoneInfo(timezone_name)).strftime("%Y-%m-%d-%H%M")


def write_reddit_radar_artifacts(
    digest: dict[str, Any],
    *,
    output_root: Path = DEFAULT_ARTIFACT_ROOT,
    timezone_name: str = "Europe/Warsaw",
) -> dict[str, Path]:
    stamp = digest_stamp(digest, timezone_name=timezone_name)
    data_dir = output_root / "data"
    runs_dir = output_root / "runs"
    data_dir.mkdir(parents=True, exist_ok=True)
    runs_dir.mkdir(parents=True, exist_ok=True)

    raw_path = data_dir / f"{stamp}-reddit-radar-raw.json"
    final_path = data_dir / f"{stamp}-reddit-radar.json"
    markdown_path = runs_dir / f"{stamp}-reddit-radar.md"

    raw_digest = digest_with_comment_analysis_defaults(digest)
    raw_path.write_text(json.dumps(raw_digest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    final_digest = public_digest_payload(digest)
    final_path.write_text(json.dumps(final_digest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    markdown_path.write_text(reddit_radar_markdown(raw_digest, stamp=stamp), encoding="utf-8")
    return {"raw": raw_path, "final": final_path, "markdown": markdown_path}


def reddit_radar_markdown(digest: dict[str, Any], *, stamp: str) -> str:
    lines = [
        f"# Reddit Radar {stamp}",
        "",
        "Status: Material update",
        "",
        f"Summary: {clean_text(digest.get('summary'))}",
        "",
        "## Analiza komentarzy",
        "",
    ]
    items = digest.get("items") if isinstance(digest.get("items"), list) else []
    if not items:
        lines.extend(["Brak bezpiecznych tematów do analizy.", ""])
        return "\n".join(lines)
    for item in items:
        if not isinstance(item, dict):
            continue
        lines.extend(
            [
                f"### {clean_text(item.get('title'))}",
                "",
                f"- Subreddit: {clean_text(item.get('sourceName'))}",
                f"- Kategorie: {clean_text(item.get('categoryLabel')) or ', '.join(item.get('tags') or []) or 'trend'}",
                f"- Score/comments: {item.get('score') or 0}/{item.get('comments') or 0}",
                f"- Status analizy komentarzy: {clean_text(item.get('commentAnalysisStatus')) or 'brak'}",
            ]
        )
        analysis_source = clean_text(item.get("commentAnalysisSource"))
        if analysis_source:
            lines.append(f"- Źródło analizy komentarzy: {analysis_source}")
        analysis_note = clean_text(item.get("commentAnalysisNote"))
        if analysis_note:
            lines.append(f"- Notatka analizy: {analysis_note}")
        post_text = clean_text(item.get("postText"))
        if post_text:
            lines.append(f"- Post: {post_text}")
        why_funny = clean_text(item.get("whyFunny"))
        if why_funny:
            lines.append(f"- Dlaczego temat działa: {why_funny}")
        highlights = item.get("commentHighlights") if isinstance(item.get("commentHighlights"), list) else []
        if not highlights:
            lines.extend(["", "Brak bezpiecznych komentarzy do pokazania w tym temacie.", ""])
            continue
        lines.append("")
        for index, highlight in enumerate(highlights, start=1):
            if not isinstance(highlight, dict):
                continue
            lines.extend(
                [
                    f"{index}. Czego dotyczy: {clean_text(highlight.get('summary'))}",
                    f"   Dlaczego ciekawe/smieszne: {clean_text(highlight.get('explanation'))}",
                ]
            )
            score = highlight.get("score")
            if isinstance(score, int) and score > 0:
                lines.append(f"   Score: {score}")
        lines.append("")
    return "\n".join(lines).rstrip() + "\n"


def collect_posts_from_safari(subreddits: list[str]) -> list[dict[str, Any]]:
    posts: list[dict[str, Any]] = []
    for subreddit in subreddits:
        source_name = f"r/{subreddit}"
        url = f"https://www.reddit.com/r/{subreddit}/hot/"
        for post in safari_extract_url(url):
            if isinstance(post, dict):
                post["sourceName"] = source_name
                posts.append(post)
    return posts


def enrich_items_from_safari(items: list[dict[str, Any]]) -> list[dict[str, Any]]:
    enriched: list[dict[str, Any]] = []
    for item in items:
        next_item = dict(item)
        source_url = clean_text(item.get("sourceURL"))
        needs_detail = not next_item.get("postText") or not next_item.get("commentHighlights")
        if source_url and needs_detail:
            try:
                detail = safari_extract_post_detail(source_url)
            except Exception:
                detail = {}
            post_text = shorten_text(detail.get("postText"), 600)
            if post_text and not next_item.get("postText"):
                next_item["postText"] = post_text
            highlights = comment_highlights_from(detail.get("commentSnippets"))
            if isinstance(detail.get("commentSnippets"), list):
                next_item["rawCommentSnippets"] = detail["commentSnippets"]
                highlights = comment_highlights_from(
                    detail.get("commentSnippets"),
                    title=clean_text(next_item.get("title")),
                    category_label=clean_text(next_item.get("categoryLabel")),
                )
            if highlights and not next_item.get("commentHighlights"):
                next_item["commentHighlights"] = highlights
        enriched.append(next_item)
    return enriched


def safari_extract_url(url: str) -> list[dict[str, Any]]:
    script = f"""
tell application "Safari"
    if (count of documents) = 0 then make new document
    set URL of front document to {json.dumps(url)}
    repeat 24 times
        delay 0.5
        try
            if (do JavaScript "document.readyState" in front document) is "complete" then exit repeat
        end try
    end repeat
    return do JavaScript {json.dumps(SAFARI_EXTRACT_JS)} in front document
end tell
"""
    result = subprocess.run(["osascript", "-e", script], capture_output=True, text=True, check=False)
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip() or "Safari Apple Events extraction failed")
    payload = json.loads(result.stdout)
    if not isinstance(payload, list):
        return []
    return [item for item in payload if isinstance(item, dict)]


def safari_extract_post_detail(url: str) -> dict[str, Any]:
    script = f"""
tell application "Safari"
    if (count of documents) = 0 then make new document
    set URL of front document to {json.dumps(url)}
    repeat 24 times
        delay 0.5
        try
            if (do JavaScript "document.readyState" in front document) is "complete" then exit repeat
        end try
    end repeat
    return do JavaScript {json.dumps(SAFARI_POST_DETAIL_JS)} in front document
end tell
"""
    result = subprocess.run(["osascript", "-e", script], capture_output=True, text=True, check=False)
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip() or "Safari Apple Events post extraction failed")
    payload = json.loads(result.stdout)
    return payload if isinstance(payload, dict) else {}


def post_digest(digest: dict[str, Any], *, notifier_url: str, token: str) -> dict[str, Any]:
    if not token.strip():
        raise RuntimeError("PAVBOT_HUMOR_INGEST_TOKEN is required when --post is used")
    url = notifier_url.rstrip("/") + "/v1/humor/digest"
    request = urllib.request.Request(
        url,
        data=json.dumps(digest).encode("utf-8"),
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
            "Accept": "application/json",
        },
        method="POST",
    )
    with urllib.request.urlopen(request, timeout=20) as response:
        return json.loads(response.read().decode("utf-8"))


def publish_reddit_radar_artifacts(
    *,
    artifact_root: Path,
    expected_paths: dict[str, Path],
) -> None:
    repo_root = Path(__file__).resolve().parents[1]
    topic_path = Path("research/reddit-radar")
    publish_script = repo_root / "scripts" / "pavbot_commit_and_push_outputs.sh"
    target_branch = os.environ.get("PAVBOT_PUBLISH_BRANCH", "main")

    if artifact_root.resolve() != (repo_root / topic_path).resolve():
        raise RuntimeError(
            "Reddit Radar artifact publication requires the standard "
            f"{topic_path} artifact root"
        )

    subprocess.run(
        ["bash", str(publish_script), "--isolated", str(topic_path)],
        cwd=repo_root,
        check=True,
    )
    subprocess.run(["git", "fetch", "origin", target_branch], cwd=repo_root, check=True)

    manifest_json = subprocess.run(
        ["git", "show", f"origin/{target_branch}:public/pavbot-manifest.json"],
        cwd=repo_root,
        check=True,
        capture_output=True,
        text=True,
    ).stdout
    manifest = json.loads(manifest_json)
    manifest_paths = {
        artifact.get("path")
        for artifact in manifest.get("artifacts", [])
        if isinstance(artifact, dict)
    }

    missing_manifest_paths: list[str] = []
    missing_remote_paths: list[str] = []
    for path in expected_paths.values():
        rel_path = str(path.resolve().relative_to(repo_root) if path.is_absolute() else path)
        if rel_path not in manifest_paths:
            missing_manifest_paths.append(rel_path)
        remote_check = subprocess.run(
            ["git", "cat-file", "-e", f"origin/{target_branch}:{rel_path}"],
            cwd=repo_root,
            check=False,
            capture_output=True,
            text=True,
        )
        if remote_check.returncode != 0:
            missing_remote_paths.append(rel_path)

    if missing_manifest_paths or missing_remote_paths:
        messages = []
        if missing_manifest_paths:
            messages.append("missing from remote manifest: " + ", ".join(sorted(missing_manifest_paths)))
        if missing_remote_paths:
            messages.append(f"missing from origin/{target_branch}: " + ", ".join(sorted(missing_remote_paths)))
        raise RuntimeError("Reddit Radar publication verification failed; " + "; ".join(messages))


def parse_subreddits(value: str) -> list[str]:
    raw = value or ",".join(DEFAULT_SUBREDDITS)
    subreddits = []
    for part in raw.split(","):
        subreddit = part.strip().removeprefix("r/")
        if re.fullmatch(r"[A-Za-z0-9_]+", subreddit):
            subreddits.append(subreddit)
    return subreddits or list(DEFAULT_SUBREDDITS)


def main() -> int:
    load_env_file(Path("backend/pavbot-notifier/.env"))
    parser = argparse.ArgumentParser(description="Collect Reddit humor digest from logged-in Safari.")
    parser.add_argument("--subreddits", default=os.environ.get("PAVBOT_SAFARI_REDDIT_SUBREDDITS", ""))
    parser.add_argument("--max-items", type=int, default=int(os.environ.get("PAVBOT_DAILY_HUMOR_MAX_ITEMS", "12")))
    parser.add_argument("--interval-hours", type=int, default=int(os.environ.get("PAVBOT_DAILY_HUMOR_INTERVAL_HOURS", "2")))
    parser.add_argument("--timezone", default=os.environ.get("PAVBOT_DAILY_HUMOR_TIMEZONE", "Europe/Warsaw"))
    parser.add_argument("--notifier-url", default=os.environ.get("PAVBOT_HUMOR_NOTIFIER_URL", DEFAULT_NOTIFIER_URL))
    parser.add_argument("--artifact-root", default=os.environ.get("PAVBOT_REDDIT_RADAR_ARTIFACT_ROOT", str(DEFAULT_ARTIFACT_ROOT)))
    parser.add_argument("--replace-count", type=int, default=6)
    parser.add_argument(
        "--history-lookback-days",
        type=int,
        default=int(os.environ.get("PAVBOT_REDDIT_RADAR_HISTORY_LOOKBACK_DAYS", str(DEFAULT_HISTORY_LOOKBACK_DAYS))),
    )
    parser.add_argument("--no-artifacts", action="store_true", help="Do not write research/reddit-radar audit artifacts.")
    parser.add_argument(
        "--post-file",
        type=Path,
        help="Publish an already prepared Reddit Radar digest JSON file after pushing the matching audit artifacts to origin/main.",
    )
    parser.add_argument("--post", action="store_true", help="Publish digest to notifier /v1/humor/digest.")
    args = parser.parse_args()

    if args.post_file:
        post_file = args.post_file
        digest = json.loads(post_file.read_text(encoding="utf-8"))
        public_digest = public_digest_payload(digest if isinstance(digest, dict) else {})
        validate_digest_comment_analysis_for_publish(
            public_digest,
            raw_digest=load_matching_reddit_radar_raw_digest(post_file),
            final_path=post_file,
        )
        if post_file.name.endswith("-reddit-radar.json") and post_file.parts[-4:-1] == ("research", "reddit-radar", "data"):
            publish_reddit_radar_artifacts(
                artifact_root=DEFAULT_ARTIFACT_ROOT,
                expected_paths={
                    "raw": reddit_radar_raw_path_for(post_file),
                    "final": post_file,
                    "markdown": reddit_radar_markdown_path_for(post_file),
                },
            )
        result = post_digest(
            public_digest,
            notifier_url=args.notifier_url,
            token=os.environ.get("PAVBOT_HUMOR_INGEST_TOKEN", ""),
        )
        print(json.dumps({"postResult": result, "digest": public_digest}, ensure_ascii=False, indent=2))
        return 0

    posts = collect_posts_from_safari(parse_subreddits(args.subreddits))
    generated_at = datetime.now(timezone.utc)
    max_items = max(1, min(args.max_items, 12))
    replace_count = max(1, min(args.replace_count, max_items))
    fresh_items = curate_posts(posts, max_items=max(max_items + replace_count, max_items))
    if not fresh_items:
        raise RuntimeError("Safari Reddit collector did not find usable non-NSFW Reddit posts")
    artifact_root = Path(args.artifact_root)
    recent_history_keys = load_recent_reddit_radar_history_keys(
        artifact_root,
        generated_at=generated_at,
        lookback_days=max(0, args.history_lookback_days),
    )
    if recent_history_keys:
        fresh_items = [
            item for item in fresh_items if reddit_radar_item_key(item) not in recent_history_keys
        ]
    if not fresh_items:
        raise RuntimeError(
            "Safari Reddit collector did not find usable non-duplicate Reddit posts "
            f"outside the last {max(0, args.history_lookback_days)} days of radar history"
        )
    previous_items = load_reddit_radar_state(artifact_root)
    items = merge_reddit_radar_items(
        previous_items,
        fresh_items,
        max_items=max_items,
        replace_count=replace_count,
        generated_at=generated_at,
    )
    items = enrich_items_from_safari(items)
    digest = build_digest(
        items=items,
        generated_at=generated_at,
        interval_hours=max(1, args.interval_hours),
        timezone_name=args.timezone,
    )
    artifact_paths: dict[str, Path] = {}
    if not args.no_artifacts:
        state_path = save_reddit_radar_state(artifact_root, items=items, generated_at=generated_at)
        artifact_paths = write_reddit_radar_artifacts(
            digest,
            output_root=artifact_root,
            timezone_name=args.timezone,
        )
        artifact_paths["state"] = state_path
        publish_reddit_radar_artifacts(
            artifact_root=artifact_root,
            expected_paths={key: path for key, path in artifact_paths.items() if key != "state"},
        )
    public_digest = public_digest_payload(digest)
    if args.post:
        validate_digest_comment_analysis_for_publish(
            public_digest,
            raw_digest=digest_with_comment_analysis_defaults(digest),
        )
        result = post_digest(
            public_digest,
            notifier_url=args.notifier_url,
            token=os.environ.get("PAVBOT_HUMOR_INGEST_TOKEN", ""),
        )
        payload: dict[str, Any] = {"postResult": result, "digest": public_digest}
        if artifact_paths:
            payload["artifacts"] = {key: str(path) for key, path in artifact_paths.items()}
        print(json.dumps(payload, ensure_ascii=False, indent=2))
    else:
        print(json.dumps(public_digest, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        raise SystemExit(1)
