from __future__ import annotations

import asyncio
import os
from dataclasses import dataclass
from datetime import date, datetime, time, timedelta, timezone
from pathlib import Path
from typing import Any, Callable
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from .core import delivery_status, load_json, save_json, send_apns_alert_safely


WARSAW_LATITUDE = 51.1079
WARSAW_LONGITUDE = 17.0385


class DailyWeatherRefreshLocked(Exception):
    def __init__(self, *, retry_at: datetime, last_report: dict[str, Any] | None = None) -> None:
        super().__init__(f"Manual weather refresh is locked until {retry_at.isoformat()}")
        self.retry_at = retry_at
        self.last_report = last_report


@dataclass(frozen=True)
class DailyWeatherConfig:
    enabled: bool
    local_time: time
    timezone_name: str
    city: str
    latitude: float
    longitude: float

    @property
    def zoneinfo(self) -> ZoneInfo:
        try:
            return ZoneInfo(self.timezone_name)
        except ZoneInfoNotFoundError:
            return ZoneInfo("Europe/Warsaw")

    def with_location(
        self,
        *,
        latitude: float | None,
        longitude: float | None,
        city: str | None,
    ) -> "DailyWeatherConfig":
        if latitude is None or longitude is None:
            return self
        return DailyWeatherConfig(
            enabled=self.enabled,
            local_time=self.local_time,
            timezone_name=self.timezone_name,
            city=(city or self.city).strip() or self.city,
            latitude=latitude,
            longitude=longitude,
        )

    @classmethod
    def from_env(cls) -> "DailyWeatherConfig":
        return cls(
            enabled=parse_bool(os.environ.get("PAVBOT_DAILY_WEATHER_ENABLED", "false")),
            local_time=parse_time(os.environ.get("PAVBOT_DAILY_WEATHER_TIME", "07:30")),
            timezone_name=os.environ.get("PAVBOT_DAILY_WEATHER_TIMEZONE", "Europe/Warsaw"),
            city=os.environ.get("PAVBOT_DAILY_WEATHER_CITY", "Wrocław"),
            latitude=float(os.environ.get("PAVBOT_DAILY_WEATHER_LAT", str(WARSAW_LATITUDE))),
            longitude=float(os.environ.get("PAVBOT_DAILY_WEATHER_LON", str(WARSAW_LONGITUDE))),
        )


def parse_bool(value: str) -> bool:
    return value.strip().lower() in {"1", "true", "yes", "on", "enabled"}


def parse_time(value: str) -> time:
    try:
        hour, minute = value.strip().split(":", maxsplit=1)
        return time(hour=int(hour), minute=int(minute))
    except Exception:
        return time(hour=7, minute=30)


def next_daily_weather_run(now: datetime, config: DailyWeatherConfig) -> datetime:
    local_now = now.astimezone(config.zoneinfo)
    run_at = datetime.combine(local_now.date(), config.local_time, tzinfo=config.zoneinfo)
    if run_at <= local_now:
        run_at += timedelta(days=1)
    return run_at


async def daily_weather_scheduler_loop(
    *,
    config_factory: Callable[[], DailyWeatherConfig],
    storage_dir: Path,
    sender_factory: Callable[[], Any],
    sleep: Callable[[float], Any] = asyncio.sleep,
) -> None:
    while True:
        config = config_factory()
        if not config.enabled:
            await sleep(60)
            continue

        now = datetime.now(timezone.utc)
        next_run = next_daily_weather_run(now, config)
        await sleep(max(1, (next_run - now.astimezone(config.zoneinfo)).total_seconds()))
        await run_daily_weather_once(
            config=config,
            storage_dir=storage_dir,
            sender=sender_factory(),
        )


async def hourly_weather_scheduler_loop(
    *,
    config_factory: Callable[[], DailyWeatherConfig],
    storage_dir: Path,
    sleep: Callable[[float], Any] = asyncio.sleep,
) -> None:
    refresh_immediately = True
    while True:
        config = config_factory()
        if not config.enabled:
            refresh_immediately = True
            await sleep(60)
            continue

        if refresh_immediately:
            try:
                await run_hourly_weather_refresh_once(
                    config=config,
                    storage_dir=storage_dir,
                    generated_at=datetime.now(timezone.utc),
                )
            except Exception:
                pass
            refresh_immediately = False
            continue

        now = datetime.now(timezone.utc)
        next_run = next_hourly_weather_refresh(now, config)
        await sleep(max(1, (next_run - now.astimezone(config.zoneinfo)).total_seconds()))
        try:
            await run_hourly_weather_refresh_once(
                config=config,
                storage_dir=storage_dir,
                generated_at=datetime.now(timezone.utc),
            )
        except Exception:
            pass


async def run_daily_weather_once(
    *,
    config: DailyWeatherConfig,
    storage_dir: Path,
    sender: Any,
    force: bool = False,
) -> dict[str, Any]:
    state_path = storage_dir / "last-daily-weather.json"
    state = load_json(state_path, {})
    now = datetime.now(timezone.utc)
    local_today = now.astimezone(config.zoneinfo).date().isoformat()

    if not force and state.get("lastRunDate") == local_today:
        state["lastSkippedAt"] = now.isoformat()
        state["lastSkipReason"] = "Daily weather already sent for this local date"
        save_json(state_path, state)
        return {
            "status": "skipped",
            "skippedReason": state["lastSkipReason"],
            "date": local_today,
        }

    try:
        report = await fetch_daily_weather_report(config=config, generated_at=now)
        devices = load_json(storage_dir / "devices.json", {})
        delivery = await send_daily_weather_notifications(
            devices=devices,
            report=report,
            sender=sender,
        )
        next_run = next_daily_weather_run(now, config).isoformat()
        state = {
            **state,
            "lastReport": report,
            "lastDelivery": delivery,
            "lastError": None,
            "nextRun": next_run,
        }
        if force:
            state["lastForcedRunAt"] = now.isoformat()
            state["lastForcedRunDate"] = local_today
        else:
            state["lastRunAt"] = now.isoformat()
            state["lastRunDate"] = local_today
        save_json(state_path, state)
        return {
            "status": "processed",
            "report": report,
            "delivery": delivery,
        }
    except Exception as exc:
        error_state = {
            **state,
            "lastError": {
                "recordedAt": now.isoformat(),
                "error": str(exc),
                "errorType": type(exc).__name__,
            },
            "nextRun": next_daily_weather_run(now, config).isoformat(),
        }
        save_json(state_path, error_state)
        raise


async def latest_daily_weather_report(
    *,
    config: DailyWeatherConfig,
    storage_dir: Path,
    now: datetime | None = None,
) -> dict[str, Any]:
    now = now or datetime.now(timezone.utc)
    result = await run_hourly_weather_refresh_once(
        config=config,
        storage_dir=storage_dir,
        generated_at=now,
    )
    return result["report"]


async def run_hourly_weather_refresh_once(
    *,
    config: DailyWeatherConfig,
    storage_dir: Path,
    generated_at: datetime | None = None,
    force: bool = False,
) -> dict[str, Any]:
    now = generated_at or datetime.now(timezone.utc)
    state_path = storage_dir / "last-daily-weather.json"
    state = load_json(state_path, {})
    cached_report = cached_weather_report_for_config(state=state, config=config)
    cached_refresh_at = cached_weather_refresh_at_for_config(state=state, config=config)

    if (
        not force
        and cached_report is not None
        and weather_report_is_current_hour(
            report=cached_report,
            now=now,
            config=config,
            fallback_refresh_at=cached_refresh_at,
        )
    ):
        state = save_hourly_weather_state(
            state=state,
            config=config,
            report=cached_report,
            refreshed_at=cached_refresh_at or now,
            last_error=None,
        )
        save_json(state_path, state)
        return {
            "status": "skipped",
            "skippedReason": "Weather report already refreshed for this local hour",
            "report": cached_report,
            "nextHourlyRefreshAt": state.get("nextHourlyRefreshAt"),
        }

    try:
        report = await fetch_daily_weather_report(config=config, generated_at=now)
        state = save_hourly_weather_state(
            state=state,
            config=config,
            report=report,
            refreshed_at=now,
            last_error=None,
        )
        state["lastReportFetchedAt"] = now.isoformat()
        state["nextRun"] = next_daily_weather_run(now, config).isoformat()
        save_json(state_path, state)
        return {
            "status": "refreshed",
            "report": report,
            "nextHourlyRefreshAt": state.get("nextHourlyRefreshAt"),
        }
    except Exception as exc:
        error_state = save_hourly_weather_state(
            state=state,
            config=config,
            report=cached_report,
            refreshed_at=cached_refresh_at,
            last_error={
                "recordedAt": now.isoformat(),
                "error": str(exc),
                "errorType": type(exc).__name__,
            },
            now=now,
        )
        save_json(state_path, error_state)
        raise


async def refresh_daily_weather_report(
    *,
    config: DailyWeatherConfig,
    storage_dir: Path,
    generated_at: datetime | None = None,
) -> dict[str, Any]:
    now = generated_at or datetime.now(timezone.utc)
    state_path = storage_dir / "last-daily-weather.json"
    state = load_json(state_path, {})
    retry_at = manual_refresh_retry_at(state=state, now=now, config=config)
    if retry_at is not None:
        blocked_state = {
            **state,
            "lastManualRefreshBlockedAt": now.isoformat(),
            "manualRefreshRetryAt": retry_at.isoformat(),
            "nextRun": next_daily_weather_run(now, config).isoformat(),
        }
        save_json(state_path, blocked_state)
        last_report = state.get("lastReport") if isinstance(state.get("lastReport"), dict) else None
        raise DailyWeatherRefreshLocked(retry_at=retry_at, last_report=last_report)

    report = await fetch_daily_weather_report(config=config, generated_at=now)
    next_manual_refresh = next_manual_refresh_at(now, config)
    save_json(
        state_path,
        {
            **state,
            "lastReport": report,
            "lastReportFetchedAt": now.isoformat(),
            "lastManualRefreshAt": now.isoformat(),
            "manualRefreshRetryAt": next_manual_refresh.isoformat(),
            "nextRun": next_daily_weather_run(now, config).isoformat(),
        },
    )
    return {
        "status": "refreshed",
        "report": report,
    }


async def fetch_daily_weather_report(
    *,
    config: DailyWeatherConfig,
    generated_at: datetime,
) -> dict[str, Any]:
    import httpx

    params = {
        "latitude": config.latitude,
        "longitude": config.longitude,
        "timezone": config.timezone_name,
        "forecast_days": 1,
        "current": [
            "temperature_2m",
            "apparent_temperature",
            "relative_humidity_2m",
            "precipitation",
            "weather_code",
            "wind_speed_10m",
        ],
        "daily": [
            "weather_code",
            "temperature_2m_max",
            "temperature_2m_min",
            "precipitation_probability_max",
            "precipitation_sum",
            "sunrise",
            "sunset",
        ],
        "hourly": [
            "temperature_2m",
        ],
    }
    async with httpx.AsyncClient(timeout=15) as client:
        response = await client.get("https://api.open-meteo.com/v1/forecast", params=params)
        response.raise_for_status()
        return build_weather_report(
            config=config,
            payload=response.json(),
            generated_at=generated_at,
        )


def build_weather_report(
    *,
    config: DailyWeatherConfig,
    payload: dict[str, Any],
    generated_at: datetime,
) -> dict[str, Any]:
    current = payload.get("current") or {}
    daily = payload.get("daily") or {}
    report_date = daily_first(daily, "time") or generated_at.astimezone(config.zoneinfo).date().isoformat()
    report_day = date.fromisoformat(report_date)
    code = int(current.get("weather_code") or daily_first(daily, "weather_code") or 0)
    condition = weather_code_label(code)
    current_temperature = round_float(current.get("temperature_2m"))
    apparent_temperature = round_float(current.get("apparent_temperature"))
    min_temperature = round_float(daily_first(daily, "temperature_2m_min"))
    max_temperature = round_float(daily_first(daily, "temperature_2m_max"))
    precipitation_probability = int(daily_first(daily, "precipitation_probability_max") or 0)
    precipitation_sum = round_float(daily_first(daily, "precipitation_sum"))
    wind_speed = round_float(current.get("wind_speed_10m"))
    humidity = int(current.get("relative_humidity_2m") or 0)
    hourly_temperature = hourly_temperature_points(payload.get("hourly") or {}, report_date)
    temperature_timeline = temperature_timeline_points(
        hourly_temperature=hourly_temperature,
        report_date=report_date,
        generated_at=generated_at,
        config=config,
    )
    namedays = namedays_for_date(report_day)
    weekday = polish_weekday(report_day)
    headline = weather_headline(
        city=config.city,
        condition=condition,
        current_temperature=current_temperature,
        max_temperature=max_temperature,
        generated_at=generated_at,
        config=config,
    )
    recommendation = weather_recommendation(
        precipitation_probability=precipitation_probability,
        wind_speed=wind_speed,
        apparent_temperature=apparent_temperature or current_temperature,
        generated_at=generated_at,
        config=config,
    )

    return {
        "id": f"{slugify(config.city)}-{report_date}",
        "city": config.city,
        "date": report_date,
        "weekday": weekday,
        "generatedAt": generated_at.isoformat(),
        "nameDays": namedays,
        "headline": headline,
        "summary": (
            f"{weekday.capitalize()}, {polish_date(report_day)}. {condition}. "
            f"Temperatura od {format_number(min_temperature)}°C do {format_number(max_temperature)}°C. "
            f"Imieniny: {', '.join(namedays)}."
        ),
        "recommendation": recommendation,
        "temperature": {
            "current": current_temperature,
            "apparent": apparent_temperature,
            "min": min_temperature,
            "max": max_temperature,
            "unit": "°C",
        },
        "conditions": {
            "code": code,
            "label": condition,
        },
        "precipitation": {
            "probability": precipitation_probability,
            "total": precipitation_sum,
            "unit": "mm",
        },
        "wind": {
            "speed": wind_speed,
            "unit": "km/h",
        },
        "humidity": humidity,
        "sunrise": daily_first(daily, "sunrise"),
        "sunset": daily_first(daily, "sunset"),
        "hourlyTemperature": hourly_temperature,
        "temperatureTimeline": temperature_timeline,
        "source": "Open-Meteo Forecast API",
    }


async def send_daily_weather_notifications(
    *,
    devices: dict[str, Any],
    report: dict[str, Any],
    sender: Any,
) -> dict[str, Any]:
    summary: dict[str, Any] = {
        "attempted": 0,
        "sent": 0,
        "failed": 0,
        "skippedDevices": 0,
        "errors": [],
        "status": "skipped",
        "apnsConfigured": bool(getattr(getattr(sender, "config", None), "is_configured", True)),
    }
    if not summary["apnsConfigured"]:
        summary["skippedReason"] = "APNs is not configured"
        return summary

    for device_token, registration in devices.items():
        if not isinstance(registration, dict):
            summary["skippedDevices"] += 1
            continue
        if not registration.get("dailyWeatherEnabled", False):
            summary["skippedDevices"] += 1
            continue
        await send_apns_alert_safely(
            sender=sender,
            device_token=device_token,
            title="Dzień dobry z Pavbot",
            body=daily_weather_push_body(report),
            user_info={
                "notificationKind": "dailyWeather",
                "weatherDate": report.get("date", ""),
                "city": report.get("city", "Wrocław"),
                "reportID": report.get("id", ""),
            },
            summary=summary,
            kind="dailyWeather",
            item_id=report.get("id", ""),
        )

    summary["status"] = delivery_status(summary)
    return summary


def daily_weather_status(
    *,
    storage_dir: Path,
    config: DailyWeatherConfig,
    now: datetime | None = None,
) -> dict[str, Any]:
    now = now or datetime.now(timezone.utc)
    state = load_json(storage_dir / "last-daily-weather.json", {})
    return {
        "enabled": config.enabled,
        "city": config.city,
        "time": config.local_time.strftime("%H:%M"),
        "timezone": config.timezone_name,
        "nextRun": next_daily_weather_run(now, config).isoformat() if config.enabled else None,
        "lastRunAt": state.get("lastRunAt"),
        "lastRunDate": state.get("lastRunDate"),
        "lastDelivery": state.get("lastDelivery"),
        "lastError": state.get("lastError"),
        "lastHourlyRefreshAt": state.get("lastHourlyRefreshAt"),
        "nextHourlyRefreshAt": state.get("nextHourlyRefreshAt") or next_hourly_weather_refresh(now, config).isoformat(),
        "lastHourlyError": state.get("lastHourlyError"),
        "lastManualRefreshAt": state.get("lastManualRefreshAt"),
        "manualRefreshRetryAt": state.get("manualRefreshRetryAt"),
        "lastReport": compact_report_status(state.get("lastReport")),
        "cachedLocations": compact_cached_locations(state.get("locationReports")),
    }


def next_hourly_weather_refresh(value: datetime, config: DailyWeatherConfig) -> datetime:
    local_value = value.astimezone(config.zoneinfo)
    return local_value.replace(minute=0, second=0, microsecond=0) + timedelta(hours=1)


def weather_location_key(config: DailyWeatherConfig) -> str:
    return f"{slugify(config.city)}:{config.latitude:.4f}:{config.longitude:.4f}"


def cached_weather_report_for_config(
    *,
    state: dict[str, Any],
    config: DailyWeatherConfig,
) -> dict[str, Any] | None:
    location_state = location_state_for_config(state=state, config=config)
    report = location_state.get("lastReport")
    if isinstance(report, dict):
        return report
    legacy_report = state.get("lastReport")
    if isinstance(legacy_report, dict) and should_use_legacy_weather_cache(config=config):
        return legacy_report
    return None


def cached_weather_refresh_at_for_config(
    *,
    state: dict[str, Any],
    config: DailyWeatherConfig,
) -> datetime | None:
    location_state = location_state_for_config(state=state, config=config)
    refresh_at = parse_datetime(location_state.get("lastHourlyRefreshAt"))
    if refresh_at is not None:
        return refresh_at
    if should_use_legacy_weather_cache(config=config):
        return parse_datetime(state.get("lastHourlyRefreshAt"))
    return None


def should_use_legacy_weather_cache(*, config: DailyWeatherConfig) -> bool:
    default_config = DailyWeatherConfig.from_env()
    return weather_location_key(config) == weather_location_key(default_config)


def location_state_for_config(
    *,
    state: dict[str, Any],
    config: DailyWeatherConfig,
) -> dict[str, Any]:
    reports = state.get("locationReports")
    if not isinstance(reports, dict):
        return {}
    entry = reports.get(weather_location_key(config))
    return entry if isinstance(entry, dict) else {}


def weather_report_is_current_hour(
    *,
    report: dict[str, Any],
    now: datetime,
    config: DailyWeatherConfig,
    fallback_refresh_at: datetime | None = None,
) -> bool:
    if "temperatureTimeline" not in report:
        return False
    if "start dnia" in str(report.get("headline") or "").lower():
        return False
    generated_at = parse_datetime(report.get("generatedAt")) or fallback_refresh_at
    if generated_at is None:
        return False
    return hourly_bucket(generated_at, config) == hourly_bucket(now, config)


def hourly_bucket(value: datetime, config: DailyWeatherConfig) -> datetime:
    local_value = value.astimezone(config.zoneinfo)
    return local_value.replace(minute=0, second=0, microsecond=0)


def save_hourly_weather_state(
    *,
    state: dict[str, Any],
    config: DailyWeatherConfig,
    report: dict[str, Any] | None,
    refreshed_at: datetime | None,
    last_error: dict[str, Any] | None,
    now: datetime | None = None,
) -> dict[str, Any]:
    state = dict(state)
    effective_now = now or refreshed_at or datetime.now(timezone.utc)
    next_refresh = next_hourly_weather_refresh(effective_now, config).isoformat()
    location_key = weather_location_key(config)
    location_reports = state.get("locationReports")
    if not isinstance(location_reports, dict):
        location_reports = {}
    location_entry: dict[str, Any] = {
        "city": config.city,
        "latitude": config.latitude,
        "longitude": config.longitude,
        "timezone": config.timezone_name,
        "lastHourlyError": last_error,
        "nextHourlyRefreshAt": next_refresh,
    }
    if report is not None:
        location_entry["lastReport"] = report
        state["lastReport"] = report
    if refreshed_at is not None:
        location_entry["lastHourlyRefreshAt"] = refreshed_at.isoformat()
        state["lastHourlyRefreshAt"] = refreshed_at.isoformat()
    previous_entry = location_reports.get(location_key)
    if not isinstance(previous_entry, dict):
        previous_entry = {}
    location_reports[location_key] = {**previous_entry, **location_entry}
    state["locationReports"] = location_reports
    state["nextHourlyRefreshAt"] = next_refresh
    state["lastHourlyError"] = last_error
    return state


def compact_cached_locations(value: Any) -> list[dict[str, Any]]:
    if not isinstance(value, dict):
        return []
    locations: list[dict[str, Any]] = []
    for key, item in sorted(value.items()):
        if not isinstance(item, dict):
            continue
        locations.append(
            {
                "key": key,
                "city": item.get("city"),
                "lastHourlyRefreshAt": item.get("lastHourlyRefreshAt"),
                "nextHourlyRefreshAt": item.get("nextHourlyRefreshAt"),
                "lastReport": compact_report_status(item.get("lastReport")),
                "lastHourlyError": item.get("lastHourlyError"),
            }
        )
    return locations


def manual_refresh_retry_at(
    *,
    state: dict[str, Any],
    now: datetime,
    config: DailyWeatherConfig,
) -> datetime | None:
    last_refresh = parse_datetime(state.get("lastManualRefreshAt"))
    if last_refresh is None:
        return None
    retry_at = next_manual_refresh_at(last_refresh, config)
    if now.astimezone(config.zoneinfo) < retry_at:
        return retry_at
    return None


def next_manual_refresh_at(value: datetime, config: DailyWeatherConfig) -> datetime:
    local_value = value.astimezone(config.zoneinfo)
    return local_value.replace(minute=0, second=0, microsecond=0) + timedelta(hours=1)


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


def hourly_temperature_points(hourly: dict[str, Any], report_date: str) -> list[dict[str, Any]]:
    times = hourly.get("time")
    temperatures = hourly.get("temperature_2m")
    if not isinstance(times, list) or not isinstance(temperatures, list):
        return []

    points: list[dict[str, Any]] = []
    for time_value, temperature_value in zip(times, temperatures):
        if not isinstance(time_value, str) or not time_value.startswith(report_date):
            continue
        temperature = round_float(temperature_value)
        if temperature is None:
            continue
        points.append(
            {
                "time": time_value,
                "temperature": temperature,
                "unit": "°C",
            }
        )
    return points


def temperature_timeline_points(
    *,
    hourly_temperature: list[dict[str, Any]],
    report_date: str,
    generated_at: datetime,
    config: DailyWeatherConfig,
) -> list[dict[str, Any]]:
    if not hourly_temperature:
        return []
    local_generated_at = generated_at.astimezone(config.zoneinfo)
    if local_generated_at.date().isoformat() != report_date:
        return hourly_temperature

    start_key = local_generated_at.replace(minute=0, second=0, microsecond=0).strftime("%Y-%m-%dT%H:%M")
    timeline = [
        point
        for point in hourly_temperature
        if isinstance(point.get("time"), str) and point["time"] >= start_key
    ]
    return timeline or hourly_temperature[-1:]


def compact_report_status(report: Any) -> dict[str, Any] | None:
    if not isinstance(report, dict):
        return None
    return {
        "id": report.get("id"),
        "date": report.get("date"),
        "headline": report.get("headline"),
        "generatedAt": report.get("generatedAt"),
    }


def daily_weather_push_body(report: dict[str, Any]) -> str:
    temperature = report.get("temperature") or {}
    conditions = report.get("conditions") or {}
    city = report.get("city") or "Wrocław"
    temperature_label = format_number(temperature.get("current") or temperature.get("max"))
    condition_label = conditions.get("label") or "pogoda"
    return (
        f"Miłego dnia! Prognoza dla: {city} — {condition_label}, "
        f"{temperature_label}°C. Dotknij, aby zobaczyć Dzisiaj."
    )


def weather_headline(
    *,
    city: str,
    condition: str,
    current_temperature: float | None,
    max_temperature: float | None,
    generated_at: datetime,
    config: DailyWeatherConfig,
) -> str:
    temperature = current_temperature if current_temperature is not None else max_temperature
    local_hour = generated_at.astimezone(config.zoneinfo).hour
    moment = weather_moment_label(local_hour)
    return f"{city}: {moment}, {condition.lower()} i {format_number(temperature)}°C"


def weather_recommendation(
    *,
    precipitation_probability: int,
    wind_speed: float | None,
    apparent_temperature: float | None,
    generated_at: datetime,
    config: DailyWeatherConfig,
) -> str:
    notes: list[str] = []
    if precipitation_probability >= 60:
        notes.append("weź parasol lub lekką kurtkę przeciwdeszczową")
    elif precipitation_probability >= 30:
        notes.append("miej pod ręką coś na przelotny deszcz")
    else:
        notes.append("większych opadów raczej nie widać")

    if wind_speed is not None and wind_speed >= 30:
        notes.append("zwróć uwagę na mocniejszy wiatr")
    if apparent_temperature is not None and apparent_temperature <= 5:
        notes.append("ubierz cieplejszą warstwę")
    elif apparent_temperature is not None and apparent_temperature >= 27:
        notes.append("pamiętaj o wodzie i lżejszym ubraniu")

    return f"{weather_recommendation_prefix(generated_at, config)}: " + "; ".join(notes) + "."


def weather_moment_label(hour: int) -> str:
    if 5 <= hour < 10:
        return "poranek"
    if 10 <= hour < 14:
        return "przedpołudnie"
    if 14 <= hour < 18:
        return "popołudnie"
    if 18 <= hour < 23:
        return "wieczór"
    return "noc"


def weather_recommendation_prefix(generated_at: datetime, config: DailyWeatherConfig) -> str:
    local_hour = generated_at.astimezone(config.zoneinfo).hour
    if 5 <= local_hour < 10:
        return "Na poranek"
    if 10 <= local_hour < 14:
        return "Na przedpołudnie"
    if 14 <= local_hour < 18:
        return "Na popołudnie"
    if 18 <= local_hour < 23:
        return "Na wieczór"
    return "Na noc"


def weather_code_label(code: int) -> str:
    if code == 0:
        return "Bezchmurnie"
    if code in {1, 2}:
        return "Częściowe zachmurzenie"
    if code == 3:
        return "Pochmurno"
    if code in {45, 48}:
        return "Mgła"
    if code in {51, 53, 55, 56, 57}:
        return "Mżawka"
    if code in {61, 63, 65, 66, 67, 80, 81, 82}:
        return "Deszcz"
    if code in {71, 73, 75, 77, 85, 86}:
        return "Śnieg"
    if code in {95, 96, 99}:
        return "Burze"
    return "Zmienna pogoda"


def daily_first(values: dict[str, Any], key: str) -> Any:
    value = values.get(key)
    if isinstance(value, list) and value:
        return value[0]
    return value


def round_float(value: Any) -> float | None:
    if value is None:
        return None
    try:
        return round(float(value), 1)
    except (TypeError, ValueError):
        return None


def format_number(value: Any) -> str:
    if value is None:
        return "--"
    try:
        number = float(value)
    except (TypeError, ValueError):
        return "--"
    if number.is_integer():
        return str(int(number))
    return f"{number:.1f}"


def polish_weekday(value: date) -> str:
    return [
        "poniedziałek",
        "wtorek",
        "środa",
        "czwartek",
        "piątek",
        "sobota",
        "niedziela",
    ][value.weekday()]


def polish_date(value: date) -> str:
    months = [
        "",
        "stycznia",
        "lutego",
        "marca",
        "kwietnia",
        "maja",
        "czerwca",
        "lipca",
        "sierpnia",
        "września",
        "października",
        "listopada",
        "grudnia",
    ]
    return f"{value.day} {months[value.month]} {value.year}"


def namedays_for_date(value: date) -> list[str]:
    key = value.strftime("%m-%d")
    return POLISH_NAMEDAYS.get(key, ["sprawdź lokalny kalendarz imienin"])


def slugify(value: str) -> str:
    replacements = {
        "ą": "a",
        "ć": "c",
        "ę": "e",
        "ł": "l",
        "ń": "n",
        "ó": "o",
        "ś": "s",
        "ż": "z",
        "ź": "z",
    }
    lowered = value.lower()
    normalized = "".join(replacements.get(character, character) for character in lowered)
    return "-".join(part for part in normalized.replace("/", " ").split() if part)


POLISH_NAMEDAYS: dict[str, list[str]] = {
    "01-01": ["Mieczysław", "Mieszko", "Maria"],
    "01-02": ["Bazyli", "Grzegorz", "Izydor"],
    "01-03": ["Genowefa", "Daniel", "Arleta"],
    "01-04": ["Eugeniusz", "Tytus", "Aniela"],
    "01-05": ["Hanna", "Edward", "Szymon"],
    "01-06": ["Kacper", "Melchior", "Baltazar"],
    "01-07": ["Lucjan", "Julian", "Rajmund"],
    "01-08": ["Seweryn", "Mścisław", "Erhard"],
    "01-09": ["Adrian", "Marcelina", "Julian"],
    "01-10": ["Wilhelm", "Dobrosław", "Danuta"],
    "01-11": ["Honorata", "Matylda", "Teodozjusz"],
    "01-12": ["Arkadiusz", "Czesława", "Greta"],
    "01-13": ["Weronika", "Bogumił", "Hilary"],
    "01-14": ["Feliks", "Nina", "Radogost"],
    "01-15": ["Paweł", "Izydor", "Arnold"],
    "01-16": ["Marceli", "Włodzimierz", "Honorata"],
    "01-17": ["Antoni", "Jan", "Rościsław"],
    "01-18": ["Piotr", "Małgorzata", "Regina"],
    "01-19": ["Henryk", "Mariusz", "Makary"],
    "01-20": ["Fabian", "Sebastian", "Dobiegniew"],
    "01-21": ["Agnieszka", "Jarosław", "Epifani"],
    "01-22": ["Wincenty", "Anastazy", "Gaudenty"],
    "01-23": ["Ildefons", "Rajmund", "Klemens"],
    "01-24": ["Franciszek", "Felicja", "Rafał"],
    "01-25": ["Paweł", "Miłosz", "Tatiana"],
    "01-26": ["Tymoteusz", "Paula", "Polikarp"],
    "01-27": ["Przybysław", "Angela", "Jerzy"],
    "01-28": ["Tomasz", "Walery", "Julian"],
    "01-29": ["Zdzisław", "Franciszek", "Sulpicjusz"],
    "01-30": ["Maciej", "Hiacynta", "Martyna"],
    "01-31": ["Jan", "Marceli", "Ludwika"],
    "02-01": ["Brygida", "Ignacy", "Seweryn"],
    "02-02": ["Maria", "Miłosława", "Kornel"],
    "02-03": ["Błażej", "Oskar", "Telimena"],
    "02-04": ["Andrzej", "Joanna", "Weronika"],
    "02-05": ["Agata", "Adelajda", "Izydor"],
    "02-06": ["Dorota", "Bohdan", "Tytus"],
    "02-07": ["Ryszard", "Romuald", "Teodor"],
    "02-08": ["Hieronim", "Józefina", "Piotr"],
    "02-09": ["Apolonia", "Eryk", "Cyryl"],
    "02-10": ["Scholastyka", "Jacek", "Elwira"],
    "02-11": ["Maria", "Lucjan", "Olga"],
    "02-12": ["Eulalia", "Benedykt", "Modest"],
    "02-13": ["Grzegorz", "Katarzyna", "Jordan"],
    "02-14": ["Walentyn", "Cyryl", "Metody"],
    "02-15": ["Faustyn", "Jowita", "Georgia"],
    "02-16": ["Danuta", "Juliana", "Samuel"],
    "02-17": ["Donat", "Łukasz", "Zbigniew"],
    "02-18": ["Szymon", "Konstancja", "Flawian"],
    "02-19": ["Konrad", "Arnold", "Marceli"],
    "02-20": ["Ludmiła", "Leon", "Zenobiusz"],
    "02-21": ["Eleonora", "Feliks", "Kiejstut"],
    "02-22": ["Małgorzata", "Marta", "Piotr"],
    "02-23": ["Damian", "Romana", "Polikarp"],
    "02-24": ["Maciej", "Bogusz", "Sergiusz"],
    "02-25": ["Cezary", "Wiktor", "Tarazjusz"],
    "02-26": ["Aleksander", "Mirosław", "Dionizy"],
    "02-27": ["Gabriel", "Anastazja", "Leonard"],
    "02-28": ["Roman", "Makary", "Ludomir"],
    "02-29": ["Lech", "August", "Hilary"],
    "03-01": ["Albina", "Radosław", "Dawid"],
    "03-02": ["Helena", "Paweł", "Symplicjusz"],
    "03-03": ["Kunikunda", "Tyberiusz", "Maryna"],
    "03-04": ["Kazimierz", "Łucja", "Adrian"],
    "03-05": ["Fryderyk", "Wacław", "Oliwia"],
    "03-06": ["Róża", "Wiktor", "Jordan"],
    "03-07": ["Tomasz", "Paweł", "Felicyta"],
    "03-08": ["Beata", "Wincenty", "Jan"],
    "03-09": ["Dominik", "Katarzyna", "Franciszka"],
    "03-10": ["Cyprian", "Makary", "Aleksander"],
    "03-11": ["Konstanty", "Ludosław", "Benedykt"],
    "03-12": ["Grzegorz", "Bernard", "Teofan"],
    "03-13": ["Krystyna", "Patrycja", "Bożena"],
    "03-14": ["Matylda", "Jakub", "Lech"],
    "03-15": ["Klemens", "Longin", "Ludwika"],
    "03-16": ["Hilary", "Izabela", "Oktawia"],
    "03-17": ["Zbigniew", "Patryk", "Gertruda"],
    "03-18": ["Cyryl", "Edward", "Anzelm"],
    "03-19": ["Józef", "Bogdan", "Marek"],
    "03-20": ["Klaudia", "Maurycy", "Aleksandra"],
    "03-21": ["Lubomir", "Benedykt", "Klemencja"],
    "03-22": ["Katarzyna", "Bogusław", "Lea"],
    "03-23": ["Pelagia", "Oktawian", "Feliks"],
    "03-24": ["Marek", "Gabriel", "Katarzyna"],
    "03-25": ["Maria", "Wieńczysław", "Ireneusz"],
    "03-26": ["Teodor", "Emanuel", "Ludger"],
    "03-27": ["Lidia", "Ernest", "Jan"],
    "03-28": ["Aniela", "Jan", "Dorotea"],
    "03-29": ["Wiktoryn", "Eustachy", "Helmut"],
    "03-30": ["Amelia", "Kwiryn", "Leonard"],
    "03-31": ["Beniamin", "Kornelia", "Balbina"],
    "04-01": ["Hugo", "Grażyna", "Teodora"],
    "04-02": ["Franciszek", "Urban", "Władysław"],
    "04-03": ["Ryszard", "Pankracy", "Benedykt"],
    "04-04": ["Izydor", "Wacław", "Benedykta"],
    "04-05": ["Irena", "Wincenty", "Waldemar"],
    "04-06": ["Celestyn", "Wilhelm", "Notker"],
    "04-07": ["Donat", "Herman", "Rufin"],
    "04-08": ["Dionizy", "Julia", "Radosław"],
    "04-09": ["Maria", "Maksym", "Dymitr"],
    "04-10": ["Michał", "Makary", "Antoni"],
    "04-11": ["Filip", "Leon", "Jaromir"],
    "04-12": ["Wiktor", "Zenon", "Juliusz"],
    "04-13": ["Przemysław", "Marcin", "Ida"],
    "04-14": ["Walerian", "Justyn", "Berenika"],
    "04-15": ["Anastazja", "Leonid", "Wacław"],
    "04-16": ["Bernadeta", "Benedykt", "Julia"],
    "04-17": ["Robert", "Rudolf", "Anicet"],
    "04-18": ["Bogusław", "Apoloniusz", "Gościsław"],
    "04-19": ["Leon", "Tymon", "Jerzy"],
    "04-20": ["Czesław", "Agnieszka", "Teodor"],
    "04-21": ["Anzelm", "Konrad", "Feliks"],
    "04-22": ["Łukasz", "Leon", "Kajus"],
    "04-23": ["Jerzy", "Wojciech", "Gerard"],
    "04-24": ["Horacy", "Grzegorz", "Aleksander"],
    "04-25": ["Marek", "Jarosław", "Erwin"],
    "04-26": ["Marzena", "Klarysa", "Ryszard"],
    "04-27": ["Zyta", "Teofil", "Piotr"],
    "04-28": ["Paweł", "Waleria", "Ludwik"],
    "04-29": ["Piotr", "Hugo", "Robert"],
    "04-30": ["Katarzyna", "Marian", "Pius"],
    "05-01": ["Józef", "Filip", "Jakub"],
    "05-02": ["Zygmunt", "Anatol", "Atanazy"],
    "05-03": ["Maria", "Aleksander", "Antonina"],
    "05-04": ["Florian", "Monika", "Waldemar"],
    "05-05": ["Irena", "Waldemar", "Gotard"],
    "05-06": ["Jan", "Jurand", "Jakub"],
    "05-07": ["Ludmiła", "Gizela", "Benedykt"],
    "05-08": ["Stanisław", "Wiktor", "Lizeta"],
    "05-09": ["Grzegorz", "Bożydar", "Karolina"],
    "05-10": ["Izydor", "Antonina", "Jan"],
    "05-11": ["Iga", "Mamert", "Franciszek"],
    "05-12": ["Pankracy", "Dominik", "Joanna"],
    "05-13": ["Serwacy", "Robert", "Gloria"],
    "05-14": ["Maciej", "Bonifacy", "Dobiesław"],
    "05-15": ["Zofia", "Izydor", "Nadzieja"],
    "05-16": ["Andrzej", "Szymon", "Ubald"],
    "05-17": ["Sławomir", "Paschalis", "Weronika"],
    "05-18": ["Eryk", "Aleksandra", "Feliks"],
    "05-19": ["Piotr", "Celestyn", "Iwo"],
    "05-20": ["Bernardyn", "Bazylia", "Teodor"],
    "05-21": ["Jan", "Wiktor", "Kryspin"],
    "05-22": ["Helena", "Wiesława", "Ryta"],
    "05-23": ["Iwona", "Dezyderiusz", "Michał"],
    "05-24": ["Joanna", "Zuzanna", "Jan"],
    "05-25": ["Grzegorz", "Magdalena", "Urban"],
    "05-26": ["Filip", "Paulina", "Ewelina"],
    "05-27": ["Augustyn", "Juliusz", "Magdalena"],
    "05-28": ["Jaromir", "Wiktor", "German"],
    "05-29": ["Maria", "Maksymilian", "Teodozja"],
    "05-30": ["Ferdynand", "Joanna", "Feliks"],
    "05-31": ["Aniela", "Petronela", "Kamila"],
    "06-01": ["Jakub", "Konrad", "Gracja"],
    "06-02": ["Marianna", "Marcelin", "Erazm"],
    "06-03": ["Leszek", "Karol", "Tamara"],
    "06-04": ["Franciszek", "Karol", "Kwiryn"],
    "06-05": ["Waleria", "Bonifacy", "Igor"],
    "06-06": ["Norbert", "Paulina", "Laurenty"],
    "06-07": ["Robert", "Wiesław", "Paweł"],
    "06-08": ["Medard", "Seweryn", "Maksymin"],
    "06-09": ["Felicjan", "Pelagia", "Diana"],
    "06-10": ["Bogumił", "Małgorzata", "Diana"],
    "06-11": ["Barnaba", "Feliks", "Paula"],
    "06-12": ["Jan", "Onufry", "Leon"],
    "06-13": ["Antoni", "Lucjan", "Gracja"],
    "06-14": ["Eliza", "Michał", "Walerian"],
    "06-15": ["Jolanta", "Witold", "Germaine"],
    "06-16": ["Alina", "Justyna", "Benon"],
    "06-17": ["Albert", "Laura", "Adolf"],
    "06-18": ["Elżbieta", "Marek", "Amand"],
    "06-19": ["Gerwazy", "Protazy", "Julianna"],
    "06-20": ["Bogna", "Florentyna", "Rafał"],
    "06-21": ["Alicja", "Alojzy", "Rudolf"],
    "06-22": ["Paulina", "Tomasz", "Jan"],
    "06-23": ["Wanda", "Zenon", "Józef"],
    "06-24": ["Jan", "Danuta", "Teodulf"],
    "06-25": ["Łucja", "Wilhelm", "Dorota"],
    "06-26": ["Jan", "Paweł", "Dawid"],
    "06-27": ["Maria", "Władysław", "Cyryl"],
    "06-28": ["Ireneusz", "Leon", "Paweł"],
    "06-29": ["Piotr", "Paweł", "Beata"],
    "06-30": ["Emilia", "Lucyna", "Teobald"],
    "07-01": ["Halina", "Marian", "Teobald"],
    "07-02": ["Maria", "Jagoda", "Urban"],
    "07-03": ["Tomasz", "Jacek", "Anatol"],
    "07-04": ["Elżbieta", "Malwina", "Teodor"],
    "07-05": ["Antoni", "Karolina", "Maria"],
    "07-06": ["Łucja", "Dominika", "Teresa"],
    "07-07": ["Estera", "Cyryl", "Metody"],
    "07-08": ["Edgar", "Elżbieta", "Adrian"],
    "07-09": ["Weronika", "Zenon", "Mikołaj"],
    "07-10": ["Amelia", "Filip", "Antoni"],
    "07-11": ["Olga", "Kalina", "Benedykt"],
    "07-12": ["Brunon", "Jan", "Weronika"],
    "07-13": ["Małgorzata", "Sara", "Ernest"],
    "07-14": ["Ulryk", "Kamil", "Marcelin"],
    "07-15": ["Henryk", "Włodzimierz", "Bonaventura"],
    "07-16": ["Maria", "Eustachy", "Benedykt"],
    "07-17": ["Aleksy", "Bogdan", "Marcelina"],
    "07-18": ["Szymon", "Erwin", "Kamil"],
    "07-19": ["Wincenty", "Wodzisław", "Marta"],
    "07-20": ["Czesław", "Hieronim", "Małgorzata"],
    "07-21": ["Daniel", "Wiktor", "Prakseda"],
    "07-22": ["Maria", "Magdalena", "Bolesława"],
    "07-23": ["Bogna", "Apolinary", "Brygida"],
    "07-24": ["Kinga", "Krystyna", "Olga"],
    "07-25": ["Jakub", "Krzysztof", "Walentina"],
    "07-26": ["Anna", "Mirosława", "Grażyna"],
    "07-27": ["Lilia", "Natalia", "Aureliusz"],
    "07-28": ["Wiktor", "Ada", "Innocenty"],
    "07-29": ["Marta", "Olaf", "Flora"],
    "07-30": ["Ludmiła", "Julita", "Piotr"],
    "07-31": ["Ignacy", "Helena", "Fabian"],
    "08-01": ["Piotr", "Alfons", "Justyna"],
    "08-02": ["Gustaw", "Karina", "Euzebiusz"],
    "08-03": ["Lidia", "Nikodem", "August"],
    "08-04": ["Dominik", "Jan", "Protazy"],
    "08-05": ["Maria", "Stanisława", "Oswald"],
    "08-06": ["Sławomir", "Jakub", "Oktawian"],
    "08-07": ["Kajetan", "Dorota", "Sykstus"],
    "08-08": ["Emil", "Cyprian", "Dominik"],
    "08-09": ["Roman", "Klara", "Teresa"],
    "08-10": ["Wawrzyniec", "Borys", "Filomena"],
    "08-11": ["Zuzanna", "Klara", "Ligia"],
    "08-12": ["Lech", "Euzebia", "Innocenty"],
    "08-13": ["Diana", "Hipolit", "Poncjan"],
    "08-14": ["Alfred", "Maksymilian", "Euzebiusz"],
    "08-15": ["Maria", "Napoleon", "Stella"],
    "08-16": ["Roch", "Joachim", "Stefan"],
    "08-17": ["Jacek", "Miron", "Anita"],
    "08-18": ["Helena", "Bronisław", "Ilona"],
    "08-19": ["Bolesław", "Juliusz", "Ludwik"],
    "08-20": ["Bernard", "Sobiesław", "Samuel"],
    "08-21": ["Joanna", "Franciszek", "Kazimiera"],
    "08-22": ["Cezary", "Maria", "Tymoteusz"],
    "08-23": ["Róża", "Apolinary", "Filip"],
    "08-24": ["Bartłomiej", "Jerzy", "Malina"],
    "08-25": ["Ludwik", "Patrycja", "Grzegorz"],
    "08-26": ["Maria", "Zefiryn", "Maksym"],
    "08-27": ["Józef", "Monika", "Cezary"],
    "08-28": ["Augustyn", "Aleksander", "Patrycja"],
    "08-29": ["Sabina", "Jan", "Racibor"],
    "08-30": ["Róża", "Szczęsny", "Adaukt"],
    "08-31": ["Bohdan", "Rajmund", "Paulina"],
    "09-01": ["Bronisław", "Idzi", "Teresa"],
    "09-02": ["Stefan", "Julian", "Tobiasz"],
    "09-03": ["Izabela", "Szymon", "Grzegorz"],
    "09-04": ["Rozalia", "Róża", "Ida"],
    "09-05": ["Dorota", "Wawrzyniec", "Herkulan"],
    "09-06": ["Beata", "Eugeniusz", "Michał"],
    "09-07": ["Regina", "Melchior", "Ryszard"],
    "09-08": ["Maria", "Adrian", "Sergiusz"],
    "09-09": ["Piotr", "Sergiusz", "Omer"],
    "09-10": ["Łukasz", "Mikołaj", "Pulcheria"],
    "09-11": ["Jacek", "Feliks", "Prot"],
    "09-12": ["Maria", "Amadeusz", "Gwidon"],
    "09-13": ["Eugenia", "Aureliusz", "Jan"],
    "09-14": ["Bernard", "Roksana", "Cyprian"],
    "09-15": ["Nikodem", "Albina", "Katarzyna"],
    "09-16": ["Kornel", "Cyprian", "Edyta"],
    "09-17": ["Justyna", "Franciszek", "Robert"],
    "09-18": ["Stanisław", "Irena", "Józef"],
    "09-19": ["January", "Konstancja", "Teodor"],
    "09-20": ["Eustachy", "Filip", "Fausta"],
    "09-21": ["Mateusz", "Hipolit", "Jonasz"],
    "09-22": ["Tomasz", "Maurycy", "Joachim"],
    "09-23": ["Tekla", "Bogusław", "Zofia"],
    "09-24": ["Gerard", "Teodor", "Maria"],
    "09-25": ["Władysław", "Kleofas", "Aurelia"],
    "09-26": ["Cyprian", "Damian", "Euzebiusz"],
    "09-27": ["Wincenty", "Damian", "Mirabela"],
    "09-28": ["Wacław", "Marek", "Salomon"],
    "09-29": ["Michał", "Gabriel", "Rafał"],
    "09-30": ["Hieronim", "Zofia", "Honoriusz"],
    "10-01": ["Teresa", "Danuta", "Remigiusz"],
    "10-02": ["Teofil", "Dionizy", "Sława"],
    "10-03": ["Gerard", "Józef", "Tereska"],
    "10-04": ["Franciszek", "Rozalia", "Edwin"],
    "10-05": ["Igor", "Apolinary", "Flawia"],
    "10-06": ["Artur", "Brunon", "Fryderyka"],
    "10-07": ["Maria", "Marek", "Justyna"],
    "10-08": ["Brygida", "Pelagia", "Laurencja"],
    "10-09": ["Arnold", "Dionizy", "Ludwik"],
    "10-10": ["Franciszek", "Daniel", "Paulina"],
    "10-11": ["Emil", "Aldona", "Aleksander"],
    "10-12": ["Maksymilian", "Eustachy", "Serafin"],
    "10-13": ["Edward", "Gerald", "Teofil"],
    "10-14": ["Bernard", "Alan", "Kalikst"],
    "10-15": ["Teresa", "Jadwiga", "Tekla"],
    "10-16": ["Jadwiga", "Gerard", "Ambroży"],
    "10-17": ["Małgorzata", "Wiktor", "Ignacy"],
    "10-18": ["Łukasz", "Julian", "Bogumił"],
    "10-19": ["Piotr", "Ziemowit", "Paweł"],
    "10-20": ["Irena", "Jan", "Kleopatra"],
    "10-21": ["Urszula", "Hilary", "Jakub"],
    "10-22": ["Halki", "Kordula", "Filip"],
    "10-23": ["Marleny", "Seweryn", "Teodor"],
    "10-24": ["Rafał", "Marcin", "Antoni"],
    "10-25": ["Inga", "Kryspin", "Daria"],
    "10-26": ["Lucjan", "Ewaryst", "Dymitr"],
    "10-27": ["Iwona", "Sabina", "Wincenty"],
    "10-28": ["Szymon", "Juda", "Tadeusz"],
    "10-29": ["Euzebia", "Wioletta", "Narcyz"],
    "10-30": ["Zenobia", "Przemysław", "Edmund"],
    "10-31": ["Urban", "Wolfgang", "Lucilla"],
    "11-01": ["Wiktoryna", "Seweryn", "Konrad"],
    "11-02": ["Bohdan", "Tobiasz", "Małgorzata"],
    "11-03": ["Hubert", "Sylwia", "Marcin"],
    "11-04": ["Karol", "Olgierd", "Emeryk"],
    "11-05": ["Elżbieta", "Sławomir", "Zachariasz"],
    "11-06": ["Feliks", "Leonard", "Melaniusz"],
    "11-07": ["Antoni", "Ernest", "Florenty"],
    "11-08": ["Seweryn", "Klaudiusz", "Godfryd"],
    "11-09": ["Teodor", "Ursyn", "Orest"],
    "11-10": ["Andrzej", "Leon", "Ludomir"],
    "11-11": ["Marcin", "Bartłomiej", "Mina"],
    "11-12": ["Renata", "Witold", "Jonasz"],
    "11-13": ["Stanisław", "Mikołaj", "Arkadiusz"],
    "11-14": ["Serafin", "Wawrzyniec", "Emil"],
    "11-15": ["Albert", "Leopold", "Roger"],
    "11-16": ["Gertruda", "Edmund", "Marek"],
    "11-17": ["Grzegorz", "Salomea", "Elżbieta"],
    "11-18": ["Roman", "Klaudyna", "Karolina"],
    "11-19": ["Elżbieta", "Seweryn", "Faustyna"],
    "11-20": ["Anatol", "Feliks", "Edmund"],
    "11-21": ["Janusz", "Konrad", "Maria"],
    "11-22": ["Cecylia", "Marek", "Maur"],
    "11-23": ["Klemens", "Adelma", "Felicja"],
    "11-24": ["Flora", "Jan", "Emir"],
    "11-25": ["Katarzyna", "Erazm", "Elżbieta"],
    "11-26": ["Konrad", "Sylwester", "Leonard"],
    "11-27": ["Walerian", "Wirgiliusz", "Maksymilian"],
    "11-28": ["Zdzisław", "Jakub", "Stefan"],
    "11-29": ["Błażej", "Saturnin", "Fryderyk"],
    "11-30": ["Andrzej", "Justyna", "Konstanty"],
    "12-01": ["Natalia", "Eligiusz", "Blanka"],
    "12-02": ["Balbina", "Paulina", "Bibiana"],
    "12-03": ["Franciszek", "Ksawery", "Lucjusz"],
    "12-04": ["Barbara", "Krystian", "Jan"],
    "12-05": ["Kryspin", "Saba", "Gerald"],
    "12-06": ["Mikołaj", "Emilian", "Jarema"],
    "12-07": ["Ambroży", "Marcin", "Agaton"],
    "12-08": ["Maria", "Wirginiusz", "Klementyna"],
    "12-09": ["Wiesław", "Leokadia", "Joanna"],
    "12-10": ["Julia", "Daniel", "Eulalia"],
    "12-11": ["Damas", "Waldemar", "Artur"],
    "12-12": ["Aleksander", "Dagmara", "Adelajda"],
    "12-13": ["Łucja", "Otylia", "Włodzisław"],
    "12-14": ["Alfred", "Izydor", "Jan"],
    "12-15": ["Celina", "Walerian", "Nina"],
    "12-16": ["Adelajda", "Albina", "Zdzisława"],
    "12-17": ["Olimpia", "Łazarz", "Florian"],
    "12-18": ["Bogusław", "Gracjan", "Laurencja"],
    "12-19": ["Urban", "Dariusz", "Anastazy"],
    "12-20": ["Bogumiła", "Dominik", "Teofil"],
    "12-21": ["Tomasz", "Piotr", "Honorata"],
    "12-22": ["Zenon", "Flawian", "Honorata"],
    "12-23": ["Sławomira", "Wiktoria", "Iwo"],
    "12-24": ["Adam", "Ewa", "Irmina"],
    "12-25": ["Anastazja", "Eugenia", "Piotr"],
    "12-26": ["Szczepan", "Dionizy", "Wrócisław"],
    "12-27": ["Jan", "Żaneta", "Fabiola"],
    "12-28": ["Antoni", "Teofila", "Cezary"],
    "12-29": ["Tomasz", "Dawid", "Dominik"],
    "12-30": ["Eugeniusz", "Irmina", "Sabina"],
    "12-31": ["Sylwester", "Melania", "Katarzyna"],
}
