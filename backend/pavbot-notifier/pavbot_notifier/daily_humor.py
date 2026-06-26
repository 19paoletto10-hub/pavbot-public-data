from __future__ import annotations

import asyncio
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

    @classmethod
    def from_env(cls) -> "DailyHumorConfig":
        subreddits = parse_subreddits(os.environ.get("PAVBOT_REDDIT_SUBREDDITS", ""))
        return cls(
            enabled=parse_bool(os.environ.get("PAVBOT_DAILY_HUMOR_ENABLED", "true")),
            interval_hours=max(1, int(os.environ.get("PAVBOT_DAILY_HUMOR_INTERVAL_HOURS", "3"))),
            timezone_name=os.environ.get("PAVBOT_DAILY_HUMOR_TIMEZONE", "Europe/Warsaw"),
            max_items=max(1, int(os.environ.get("PAVBOT_DAILY_HUMOR_MAX_ITEMS", "6"))),
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


async def latest_humor_digest(*, config: DailyHumorConfig, storage_dir: Path) -> dict[str, Any]:
    state_path = storage_dir / "last-daily-humor.json"
    state = load_json(state_path, {})
    cached = state.get("lastDigest")
    now = datetime.now(timezone.utc)
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
                "tags": tags_for_title(title, source_name),
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
        "title": humor_title(local_generated_at.hour),
        "summary": humor_summary(local_generated_at.hour, selected),
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
        "nextRefreshAt": state.get("nextRefreshAt") or next_humor_refresh(now, config).isoformat(),
        "lastRefreshAt": state.get("lastRefreshAt"),
        "lastError": state.get("lastError"),
        "lastDigest": compact_humor_digest(digest),
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
        }
        for title, caption, tags in base[:limit]
    ]


def humor_source_label(items: list[dict[str, Any]]) -> str:
    if items and all(str(item.get("sourceName") or "").startswith("Pavbot fallback") for item in items):
        return "Pavbot fallback; Reddit unavailable or not configured"
    return "Reddit trend feed"


def humor_title(hour: int) -> str:
    if 5 <= hour < 11:
        return "Poranny radar memów"
    if 11 <= hour < 16:
        return "Południowa dawka śmiechu"
    if 16 <= hour < 22:
        return "Wieczorny przegląd memów"
    return "Nocny tryb śmiechu"


def humor_summary(hour: int, items: list[dict[str, Any]]) -> str:
    top = clean_text(str(items[0].get("title") or "")) if items else "kilka lekkich tematów"
    if 5 <= hour < 11:
        return f"Na rozruch dnia wybrane są lekkie trendy i memy, które nie wymagają kawy z kroplówki. Najmocniej wybija się: {top}."
    if 11 <= hour < 16:
        return f"W środku dnia Pavbot zebrał świeże memowe sygnały do krótkiej przerwy. Najbardziej klikalny trop: {top}."
    if 16 <= hour < 22:
        return f"Na wieczór wpada krótki, trendowy przegląd humoru z sieci. Najlepiej niesie się: {top}."
    return f"Nocny zestaw jest krótki i lekki, bez ciężkiego scrollowania. Najciekawszy trop: {top}."


def playful_caption(title: str) -> str:
    cleaned = clean_text(title)
    if "deploy" in cleaned.lower():
        return "Ten typ humoru zna każdy, kto choć raz czekał na zielone CI."
    if any(token in cleaned.lower() for token in ["ai", "chatgpt", "llm"]):
        return "AI robi swoje, ludzie robią screeny, internet robi resztę."
    if len(cleaned) < 80:
        return "Krótki memowy sygnał, dobry do szybkiego przewinięcia."
    return "Dłuższy żart z aktualnego feedu, warto otworzyć źródło po kontekst."


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
