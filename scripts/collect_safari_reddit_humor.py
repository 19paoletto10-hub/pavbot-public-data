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
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any
from zoneinfo import ZoneInfo


DEFAULT_SUBREDDITS = ("Polska_wpz", "memes", "ProgrammerHumor", "Polska", "technology")
DEFAULT_NOTIFIER_URL = "https://notify.paweltanski.com"
DEFAULT_SOURCE = "Codex Safari Reddit radar"


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


def comment_highlights_from(value: Any) -> list[dict[str, Any]]:
    if not isinstance(value, list):
        return []
    highlights: list[dict[str, Any]] = []
    for raw in value:
        if isinstance(raw, dict):
            body = clean_text(raw.get("body") or raw.get("summary") or raw.get("text"))
            score = parse_int(raw.get("score"))
        else:
            body = clean_text(raw)
            score = 0
        if not body or looks_toxic(body):
            continue
        highlights.append(
            {
                "id": f"comment-{len(highlights) + 1}",
                "summary": shorten_text(body, 180),
                "explanation": "Komentarz jest zabawny, bo dopowiada codzienny absurd z wątku i zamienia go w puentę.",
                "score": score,
            }
        )
        if len(highlights) >= 3:
            break
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
                "commentHighlights": comment_highlights_from(
                    post.get("commentHighlights") or post.get("commentSnippets") or post.get("commentsList")
                ),
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
        if source_url:
            try:
                detail = safari_extract_post_detail(source_url)
            except Exception:
                detail = {}
            post_text = shorten_text(detail.get("postText"), 600)
            if post_text and not next_item.get("postText"):
                next_item["postText"] = post_text
            highlights = comment_highlights_from(detail.get("commentSnippets"))
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
    parser.add_argument("--max-items", type=int, default=int(os.environ.get("PAVBOT_DAILY_HUMOR_MAX_ITEMS", "6")))
    parser.add_argument("--interval-hours", type=int, default=int(os.environ.get("PAVBOT_DAILY_HUMOR_INTERVAL_HOURS", "2")))
    parser.add_argument("--timezone", default=os.environ.get("PAVBOT_DAILY_HUMOR_TIMEZONE", "Europe/Warsaw"))
    parser.add_argument("--notifier-url", default=os.environ.get("PAVBOT_HUMOR_NOTIFIER_URL", DEFAULT_NOTIFIER_URL))
    parser.add_argument("--post", action="store_true", help="Publish digest to notifier /v1/humor/digest.")
    args = parser.parse_args()

    posts = collect_posts_from_safari(parse_subreddits(args.subreddits))
    items = curate_posts(posts, max_items=max(1, args.max_items))
    if not items:
        raise RuntimeError("Safari Reddit collector did not find usable non-NSFW Reddit posts")
    items = enrich_items_from_safari(items)
    digest = build_digest(
        items=items,
        generated_at=datetime.now(timezone.utc),
        interval_hours=max(1, args.interval_hours),
        timezone_name=args.timezone,
    )
    if args.post:
        result = post_digest(
            digest,
            notifier_url=args.notifier_url,
            token=os.environ.get("PAVBOT_HUMOR_INGEST_TOKEN", ""),
        )
        print(json.dumps({"postResult": result, "digest": digest}, ensure_ascii=False, indent=2))
    else:
        print(json.dumps(digest, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        raise SystemExit(1)
