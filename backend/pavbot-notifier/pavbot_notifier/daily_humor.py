from __future__ import annotations

import asyncio
import html
import os
import re
from dataclasses import dataclass, field
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any, Callable
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from .core import load_json, save_json


DEFAULT_REDDIT_SUBREDDITS = ("Polska_wpz", "memes", "ProgrammerHumor")
DEFAULT_REDDIT_USER_AGENT = "PavbotNotifier/1.0 by pavbot"
DEFAULT_HUMOR_SOURCE_MODE = "reddit_oauth"


class RedditConfigurationError(RuntimeError):
    """Raised when the Reddit feed cannot be used with the current config."""


def reddit_sources_for_subreddits(
    subreddits: tuple[str, ...] | list[str],
    *,
    oauth: bool = False,
) -> list[tuple[str, str]]:
    host = "https://oauth.reddit.com" if oauth else "https://api.reddit.com"
    return [
        (f"r/{subreddit}", f"{host}/r/{subreddit}/hot?limit=12&raw_json=1")
        for subreddit in subreddits
        if subreddit
    ]


@dataclass(frozen=True)
class DailyHumorConfig:
    enabled: bool
    interval_hours: int
    timezone_name: str
    max_items: int
    source_mode: str = DEFAULT_HUMOR_SOURCE_MODE
    sources: list[tuple[str, str]] = field(
        default_factory=lambda: reddit_sources_for_subreddits(DEFAULT_REDDIT_SUBREDDITS)
    )
    reddit_client_id: str = ""
    reddit_client_secret: str = ""
    reddit_user_agent: str = DEFAULT_REDDIT_USER_AGENT
    reddit_subreddits: tuple[str, ...] = DEFAULT_REDDIT_SUBREDDITS

    @property
    def zoneinfo(self) -> ZoneInfo:
        try:
            return ZoneInfo(self.timezone_name)
        except ZoneInfoNotFoundError:
            return ZoneInfo("Europe/Warsaw")

    @property
    def reddit_oauth_configured(self) -> bool:
        return bool(self.reddit_client_id.strip() and self.reddit_client_secret.strip())

    @property
    def external_source(self) -> bool:
        return self.source_mode.strip().lower() == "external"

    @classmethod
    def from_env(cls) -> "DailyHumorConfig":
        subreddits = parse_subreddits(os.environ.get("PAVBOT_REDDIT_SUBREDDITS", ""))
        return cls(
            enabled=parse_bool(os.environ.get("PAVBOT_DAILY_HUMOR_ENABLED", "true")),
            interval_hours=max(1, int(os.environ.get("PAVBOT_DAILY_HUMOR_INTERVAL_HOURS", "3"))),
            timezone_name=os.environ.get("PAVBOT_DAILY_HUMOR_TIMEZONE", "Europe/Warsaw"),
            max_items=max(1, int(os.environ.get("PAVBOT_DAILY_HUMOR_MAX_ITEMS", "6"))),
            source_mode=os.environ.get("PAVBOT_DAILY_HUMOR_SOURCE_MODE", DEFAULT_HUMOR_SOURCE_MODE).strip()
            or DEFAULT_HUMOR_SOURCE_MODE,
            sources=reddit_sources_for_subreddits(subreddits),
            reddit_client_id=os.environ.get("PAVBOT_REDDIT_CLIENT_ID", "").strip(),
            reddit_client_secret=os.environ.get("PAVBOT_REDDIT_CLIENT_SECRET", "").strip(),
            reddit_user_agent=os.environ.get("PAVBOT_REDDIT_USER_AGENT", DEFAULT_REDDIT_USER_AGENT).strip()
            or DEFAULT_REDDIT_USER_AGENT,
            reddit_subreddits=subreddits,
        )


def parse_bool(value: str) -> bool:
    return value.strip().lower() in {"1", "true", "yes", "on", "enabled"}


def parse_subreddits(value: str) -> tuple[str, ...]:
    if not value.strip():
        return DEFAULT_REDDIT_SUBREDDITS
    cleaned: list[str] = []
    for part in value.split(","):
        subreddit = part.strip().removeprefix("r/")
        if re.fullmatch(r"[A-Za-z0-9_]+", subreddit):
            cleaned.append(subreddit)
    return tuple(cleaned) or DEFAULT_REDDIT_SUBREDDITS


async def humor_scheduler_loop(
    *,
    config_factory: Callable[[], DailyHumorConfig],
    storage_dir: Path,
    sleep: Callable[[float], Any] = asyncio.sleep,
) -> None:
    refresh_immediately = True
    while True:
        config = config_factory()
        if not config.enabled:
            await sleep(60)
            continue

        now = datetime.now(timezone.utc)
        if refresh_immediately:
            try:
                await run_humor_refresh_once(config=config, storage_dir=storage_dir, generated_at=now)
            except Exception as exc:
                save_humor_error(storage_dir=storage_dir, config=config, error=exc, generated_at=now)
            refresh_immediately = False

        next_run = next_humor_refresh(now, config)
        await sleep(max(1, (next_run - now.astimezone(config.zoneinfo)).total_seconds()))
        try:
            await run_humor_refresh_once(config=config, storage_dir=storage_dir)
        except Exception as exc:
            save_humor_error(storage_dir=storage_dir, config=config, error=exc, generated_at=datetime.now(timezone.utc))


async def latest_humor_digest(
    *,
    config: DailyHumorConfig,
    storage_dir: Path,
    now: datetime | None = None,
) -> dict[str, Any]:
    state_path = storage_dir / "last-daily-humor.json"
    state = load_json(state_path, {})
    cached = state.get("lastDigest")
    now = now or datetime.now(timezone.utc)
    if config.external_source:
        if isinstance(cached, dict):
            return cached
        return build_humor_digest(
            items=fallback_humor_items(config.max_items),
            config=config,
            generated_at=now,
        )
    if isinstance(cached, dict) and humor_digest_is_current_window(cached, now=now, config=config):
        return cached
    result = await run_humor_refresh_once(config=config, storage_dir=storage_dir, generated_at=now)
    return result["digest"]


async def run_humor_refresh_once(
    *,
    config: DailyHumorConfig,
    storage_dir: Path,
    generated_at: datetime | None = None,
    force: bool = False,
) -> dict[str, Any]:
    generated_at = generated_at or datetime.now(timezone.utc)
    state_path = storage_dir / "last-daily-humor.json"
    state = load_json(state_path, {})
    cached = state.get("lastDigest")
    if config.external_source:
        if isinstance(cached, dict):
            return {
                "status": "external-cached",
                "skippedReason": "Humor digest is supplied by external Codex Safari automation",
                "digest": cached,
            }
        return {
            "status": "fallback",
            "skippedReason": "No external Codex Safari humor digest has been published yet",
            "digest": build_humor_digest(
                items=fallback_humor_items(config.max_items),
                config=config,
                generated_at=generated_at,
            ),
        }
    if (
        not force
        and isinstance(cached, dict)
        and humor_digest_is_current_window(cached, now=generated_at, config=config)
    ):
        return {
            "status": "skipped",
            "skippedReason": "Humor digest already refreshed for this window",
            "digest": cached,
        }

    try:
        items = await fetch_humor_items(config=config)
        digest = build_humor_digest(items=items, config=config, generated_at=generated_at)
        state = {
            **state,
            "lastDigest": digest,
            "lastRefreshAt": generated_at.isoformat(),
            "nextRefreshAt": next_humor_refresh(generated_at, config).isoformat(),
            "lastError": None,
        }
        save_json(state_path, state)
        return {"status": "refreshed", "digest": digest}
    except Exception as exc:
        save_humor_error(storage_dir=storage_dir, config=config, error=exc, generated_at=generated_at)
        fallback = build_humor_digest(items=fallback_humor_items(config.max_items), config=config, generated_at=generated_at)
        if isinstance(cached, dict) and not humor_digest_uses_fallback(cached):
            return {"status": "cached", "digest": cached, "error": str(exc)}
        return {"status": "fallback", "digest": fallback, "error": str(exc)}


async def fetch_humor_items(*, config: DailyHumorConfig) -> list[dict[str, Any]]:
    if not config.reddit_oauth_configured:
        raise RedditConfigurationError(
            "Reddit OAuth credentials are not configured. Set PAVBOT_REDDIT_CLIENT_ID and "
            "PAVBOT_REDDIT_CLIENT_SECRET."
        )

    import httpx

    headers = {
        "User-Agent": config.reddit_user_agent,
        "Accept": "application/json",
    }
    async with httpx.AsyncClient(timeout=12, headers=headers, follow_redirects=True) as client:
        access_token = await fetch_reddit_access_token(client=client, config=config)
        request_headers = {"Authorization": f"Bearer {access_token}"}
        sources = reddit_sources_for_subreddits(config.reddit_subreddits, oauth=True)
        tasks = [client.get(url, headers=request_headers) for _, url in sources]
        responses = await asyncio.gather(*tasks, return_exceptions=True)

    items: list[dict[str, Any]] = []
    errors: list[str] = []
    for (source_name, _), response in zip(sources, responses):
        if isinstance(response, Exception):
            errors.append(f"{source_name}: {response}")
            continue
        if response.status_code >= 400:
            errors.append(f"{source_name}: HTTP {response.status_code}")
            continue
        payload = response.json()
        items.extend(parse_reddit_listing(payload, source_name=source_name))

    curated = curate_humor_items(items)
    if not curated:
        detail = "; ".join(errors) if errors else "Reddit returned no usable items"
        raise RuntimeError(f"Reddit humor feed unavailable: {detail}")
    return curated[: config.max_items]


async def fetch_reddit_access_token(*, client: Any, config: DailyHumorConfig) -> str:
    if not config.reddit_oauth_configured:
        raise RedditConfigurationError(
            "Reddit OAuth credentials are not configured. Set PAVBOT_REDDIT_CLIENT_ID and "
            "PAVBOT_REDDIT_CLIENT_SECRET."
        )
    response = await client.post(
        "https://www.reddit.com/api/v1/access_token",
        data={"grant_type": "client_credentials"},
        auth=(config.reddit_client_id, config.reddit_client_secret),
        headers={
            "Accept": "application/json",
            "User-Agent": config.reddit_user_agent,
        },
    )
    if response.status_code >= 400:
        raise RuntimeError(f"Reddit OAuth token request failed: HTTP {response.status_code}")
    payload = response.json()
    access_token = payload.get("access_token") if isinstance(payload, dict) else None
    if not isinstance(access_token, str) or not access_token.strip():
        raise RuntimeError("Reddit OAuth token response did not include access_token")
    return access_token


def parse_reddit_listing(payload: dict[str, Any], *, source_name: str) -> list[dict[str, Any]]:
    children = ((payload.get("data") or {}).get("children") or [])
    items: list[dict[str, Any]] = []
    for child in children:
        data = child.get("data") if isinstance(child, dict) else None
        if not isinstance(data, dict):
            continue
        if data.get("over_18") or data.get("stickied"):
            continue
        title = clean_text(str(data.get("title") or ""))
        if not title or looks_toxic(title):
            continue
        permalink = str(data.get("permalink") or "")
        source_url = "https://www.reddit.com" + permalink if permalink.startswith("/") else permalink
        image_url = reddit_image_url(data)
        tags = tags_for_title(title, source_name)
        category_label = category_label_for(tags, source_name)
        items.append(
            {
                "id": str(data.get("id") or stable_id(title)),
                "title": title,
                "caption": playful_caption(title),
                "sourceName": source_name,
                "sourceURL": source_url,
                "imageURL": image_url,
                "score": int(data.get("score") or 0),
                "comments": int(data.get("num_comments") or 0),
                "tags": tags,
                "categoryLabel": category_label,
                "postText": clean_text(str(data.get("selftext") or "")) or None,
                "whyFunny": why_funny_for(title, category_label),
                "commentHighlights": [],
            }
        )
    return items


def reddit_image_url(data: dict[str, Any]) -> str | None:
    url = str(data.get("url_overridden_by_dest") or data.get("url") or "")
    if re.search(r"\.(png|jpe?g|webp|gif)$", url, flags=re.IGNORECASE):
        return url.replace("&amp;", "&")
    preview = data.get("preview")
    images = (preview or {}).get("images") if isinstance(preview, dict) else None
    if isinstance(images, list) and images:
        source = (images[0] or {}).get("source")
        if isinstance(source, dict):
            image_url = str(source.get("url") or "")
            return image_url.replace("&amp;", "&") or None
    return None


def curate_humor_items(items: list[dict[str, Any]]) -> list[dict[str, Any]]:
    seen: set[str] = set()
    curated: list[dict[str, Any]] = []
    for item in sorted(items, key=lambda value: (value.get("score") or 0, value.get("comments") or 0), reverse=True):
        key = clean_text(str(item.get("title") or "")).lower()
        if not key or key in seen:
            continue
        seen.add(key)
        curated.append(item)
    return curated


def build_humor_digest(
    *,
    items: list[dict[str, Any]],
    config: DailyHumorConfig,
    generated_at: datetime,
) -> dict[str, Any]:
    local_generated_at = generated_at.astimezone(config.zoneinfo)
    next_refresh = next_humor_refresh(generated_at, config)
    selected = items[: config.max_items] or fallback_humor_items(config.max_items)
    return {
        "id": f"humor-{local_generated_at.strftime('%Y-%m-%d-%H')}",
        "title": "<RR> Reddit Radar",
        "summary": humor_summary(selected),
        "generatedAt": generated_at.isoformat(),
        "displayTime": local_generated_at.strftime("%H:%M"),
        "nextRefreshAt": next_refresh.isoformat(),
        "refreshIntervalHours": config.interval_hours,
        "items": selected,
        "source": humor_source_label(selected),
    }


def daily_humor_status(*, storage_dir: Path, config: DailyHumorConfig, now: datetime | None = None) -> dict[str, Any]:
    now = now or datetime.now(timezone.utc)
    state = load_json(storage_dir / "last-daily-humor.json", {})
    digest = state.get("lastDigest") if isinstance(state.get("lastDigest"), dict) else None
    return {
        "enabled": config.enabled,
        "intervalHours": config.interval_hours,
        "timezone": config.timezone_name,
        "sourceMode": config.source_mode,
        "nextRefreshAt": state.get("nextRefreshAt") or next_humor_refresh(now, config).isoformat(),
        "lastRefreshAt": state.get("lastRefreshAt"),
        "lastError": state.get("lastError"),
        "lastDigest": compact_humor_digest(digest),
        "producer": state.get("producer"),
        "redditOAuthConfigured": config.reddit_oauth_configured,
        "redditSubreddits": list(config.reddit_subreddits),
        "sources": [{"name": name, "url": url} for name, url in config.sources],
    }


def next_humor_refresh(value: datetime, config: DailyHumorConfig) -> datetime:
    local_value = value.astimezone(config.zoneinfo)
    bucket_hour = (local_value.hour // config.interval_hours) * config.interval_hours
    bucket_start = local_value.replace(hour=bucket_hour, minute=0, second=0, microsecond=0)
    return bucket_start + timedelta(hours=config.interval_hours)


def humor_digest_is_current_window(digest: dict[str, Any], *, now: datetime, config: DailyHumorConfig) -> bool:
    if humor_digest_uses_fallback(digest):
        return False
    generated_at = parse_datetime(digest.get("generatedAt"))
    if generated_at is None:
        return False
    return humor_bucket(generated_at, config) == humor_bucket(now, config)


def humor_digest_uses_fallback(digest: dict[str, Any]) -> bool:
    if "fallback" in str(digest.get("source") or "").lower():
        return True
    items = digest.get("items")
    if isinstance(items, list) and items:
        return all(str((item or {}).get("sourceName") or "").startswith("Pavbot fallback") for item in items)
    return False


def humor_bucket(value: datetime, config: DailyHumorConfig) -> datetime:
    local_value = value.astimezone(config.zoneinfo)
    bucket_hour = (local_value.hour // config.interval_hours) * config.interval_hours
    return local_value.replace(hour=bucket_hour, minute=0, second=0, microsecond=0)


def save_humor_error(*, storage_dir: Path, config: DailyHumorConfig, error: Exception, generated_at: datetime) -> None:
    state_path = storage_dir / "last-daily-humor.json"
    state = load_json(state_path, {})
    state["lastError"] = {
        "type": type(error).__name__,
        "message": str(error),
        "at": generated_at.isoformat(),
    }
    state["nextRefreshAt"] = next_humor_refresh(generated_at, config).isoformat()
    save_json(state_path, state)


def save_external_humor_digest(
    *,
    digest: dict[str, Any],
    storage_dir: Path,
    received_at: datetime | None = None,
) -> dict[str, Any]:
    received_at = received_at or datetime.now(timezone.utc)
    state_path = storage_dir / "last-daily-humor.json"
    state = load_json(state_path, {})
    state["lastDigest"] = digest
    state["lastRefreshAt"] = received_at.isoformat()
    state["nextRefreshAt"] = digest.get("nextRefreshAt")
    state["lastError"] = None
    state["producer"] = "codex-safari"
    save_json(state_path, state)
    return {"status": "stored", "digest": digest}


def humor_ingest_token_is_valid(authorization: str | None, *, expected_token: str) -> bool:
    expected_token = expected_token.strip()
    if not expected_token or not authorization:
        return False
    scheme, _, token = authorization.partition(" ")
    return scheme.lower() == "bearer" and token.strip() == expected_token


def compact_humor_digest(digest: dict[str, Any] | None) -> dict[str, Any] | None:
    if not isinstance(digest, dict):
        return None
    return {
        "id": digest.get("id"),
        "title": digest.get("title"),
        "generatedAt": digest.get("generatedAt"),
        "itemCount": len(digest.get("items") or []),
    }


def fallback_humor_items(limit: int) -> list[dict[str, Any]]:
    base = [
        ("Kiedy deploy przechodzi za pierwszym razem", "Zespół patrzy na CI jak na zjawisko paranormalne.", ["devops", "tech"]),
        ("Mój backlog po weekendzie", "Wygląda jak mały todo-list, dopóki go nie otworzysz.", ["praca", "produktywność"]),
        ("AI miało oszczędzić czas", "Na razie wygrało konkurencję w tworzeniu nowych pomysłów do sprawdzenia.", ["AI", "codzienność"]),
        ("Najkrótszy żart programisty", "Działa u mnie.", ["programowanie"]),
        ("Plan na dziś: szybko ogarnąć", "Narrator: nie ogarnął szybko.", ["dzień", "życie"]),
        ("Kiedy ktoś mówi: tylko mała poprawka UI", "I nagle projekt poznaje trzy nowe stany brzegowe.", ["iOS", "UI"]),
    ]
    return [
        {
            "id": stable_id(title),
            "title": title,
            "caption": caption,
            "sourceName": "Pavbot fallback",
            "sourceURL": "",
            "imageURL": None,
            "score": None,
            "comments": None,
            "tags": tags,
            "categoryLabel": category_label_for(tags, "Pavbot fallback"),
            "postText": None,
            "whyFunny": why_funny_for(title, category_label_for(tags, "Pavbot fallback")),
            "commentHighlights": [],
        }
        for title, caption, tags in base[:limit]
    ]


def humor_source_label(items: list[dict[str, Any]]) -> str:
    if items and all(str(item.get("sourceName") or "").startswith("Pavbot fallback") for item in items):
        return "Pavbot fallback; Reddit unavailable or not configured"
    return "Reddit trend feed"


def humor_summary(items: list[dict[str, Any]]) -> str:
    if not items:
        return "Kategorie: trend. Najmocniej wybija się: <u>kilka lekkich tematów</u>."
    categories: list[str] = []
    for item in items:
        label = clean_text(str(item.get("categoryLabel") or ""))
        if not label:
            tags = item.get("tags") if isinstance(item.get("tags"), list) else []
            label = category_label_for(tags, str(item.get("sourceName") or ""))
        for raw_part in label.split(","):
            part = clean_text(raw_part)
            if part and part not in categories:
                categories.append(part)
    top = html.escape(clean_text(str(items[0].get("title") or "")) or "kilka lekkich tematów", quote=False)
    return f"Kategorie: {', '.join(categories[:5]) or 'trend'}. Najmocniej wybija się: <u>{top}</u>."


def playful_caption(title: str) -> str:
    cleaned = clean_text(title)
    if "deploy" in cleaned.lower():
        return "Ten typ humoru zna każdy, kto choć raz czekał na zielone CI."
    if any(token in cleaned.lower() for token in ["ai", "chatgpt", "llm"]):
        return "AI robi swoje, ludzie robią screeny, internet robi resztę."
    if len(cleaned) < 80:
        return "Krótki memowy sygnał, dobry do szybkiego przewinięcia."
    return "Dłuższy żart z aktualnego feedu, warto otworzyć źródło po kontekst."


def category_label_for(tags: list[str], source_name: str) -> str:
    values: list[str] = []
    for tag in tags:
        normalized = clean_text(str(tag))
        if not normalized or normalized.lower() == "trend":
            continue
        if normalized not in values:
            values.append(normalized)
    if len(values) > 1:
        values = [value for value in values if value.lower() != "memy"] or values
    if not values:
        source = clean_text(source_name).removeprefix("r/")
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


def tags_for_title(title: str, source_name: str) -> list[str]:
    corpus = f"{title} {source_name}".lower()
    tags: list[str] = []
    if any(value in corpus for value in ["ai", "chatgpt", "llm", "openai"]):
        tags.append("AI")
    if any(value in corpus for value in ["programmer", "code", "bug", "deploy", "dev"]):
        tags.append("dev")
    if "polska" in corpus or "wpz" in corpus:
        tags.append("PL")
    if "meme" in corpus:
        tags.append("memy")
    return tags[:3] or ["trend"]


def clean_text(value: str) -> str:
    return re.sub(r"\s+", " ", value).strip()


def looks_toxic(value: str) -> bool:
    lowered = value.lower()
    blocked = ["nsfw", "porn", "gore", "kill yourself"]
    return any(token in lowered for token in blocked)


def stable_id(value: str) -> str:
    cleaned = re.sub(r"[^a-zA-Z0-9]+", "-", value.lower()).strip("-")
    return cleaned[:64] or "humor-item"


def parse_datetime(value: Any) -> datetime | None:
    if not isinstance(value, str) or not value.strip():
        return None
    try:
        parsed = datetime.fromisoformat(value)
    except ValueError:
        return None
    if parsed.tzinfo is None:
        return parsed.replace(tzinfo=timezone.utc)
    return parsed
