#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any


TOPIC = "puls-dnia-news"
MIN_ITEMS = 12
REQUIRED_FIELDS = {
    "schemaVersion",
    "topic",
    "runDate",
    "runTime",
    "status",
    "headline",
    "summary",
    "items",
    "checkedSources",
}
REQUIRED_ITEM_FIELDS = {
    "id",
    "section",
    "title",
    "lead",
    "whatHappened",
    "keyFacts",
    "reactions",
    "whyItMatters",
    "context",
    "watchNext",
    "sources",
    "tags",
    "priority",
}


def validate_file(path: Path) -> list[str]:
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        return [f"invalid JSON: {exc.msg}"]
    except OSError as exc:
        return [f"cannot read file: {exc}"]
    return validate_payload(payload)


def validate_payload(payload: Any) -> list[str]:
    errors: list[str] = []
    if not isinstance(payload, dict):
        return ["top-level payload must be an object"]

    for field in sorted(REQUIRED_FIELDS):
        if field not in payload:
            errors.append(f"missing required field: {field}")

    if payload.get("schemaVersion") != 1:
        errors.append("schemaVersion must be 1")
    if payload.get("topic") != TOPIC:
        errors.append(f"topic must be {TOPIC}")

    for field in ("runDate", "runTime", "status", "headline", "summary"):
        if field in payload and not non_empty_string(payload[field]):
            errors.append(f"{field} must be a non-empty string")

    validate_sources(payload.get("checkedSources"), errors, "checkedSources")
    validate_items(payload.get("items"), errors)
    return errors


def validate_items(value: Any, errors: list[str]) -> None:
    if not isinstance(value, list):
        errors.append("items must be a list")
        return

    if len(value) < MIN_ITEMS:
        errors.append(f"items must contain at least {MIN_ITEMS} items")
    if len(value) % 2 != 0:
        errors.append("items count must be even so iOS can render paired cards")

    poland_count = 0
    world_count = 0
    for index, item in enumerate(value):
        prefix = f"items[{index}]"
        if not isinstance(item, dict):
            errors.append(f"{prefix} must be an object")
            continue

        for field in sorted(REQUIRED_ITEM_FIELDS):
            if field not in item:
                errors.append(f"{prefix} missing required field: {field}")

        for field in ("id", "section", "title", "lead", "whatHappened", "whyItMatters", "context", "priority"):
            if field in item and not non_empty_string(item[field]):
                errors.append(f"{prefix}.{field} must be a non-empty string")

        validate_string_list(item.get("keyFacts"), f"{prefix}.keyFacts", errors, min_items=1)
        validate_string_list(item.get("reactions"), f"{prefix}.reactions", errors, min_items=1)
        validate_string_list(item.get("watchNext"), f"{prefix}.watchNext", errors, min_items=1)
        validate_string_list(item.get("tags"), f"{prefix}.tags", errors, min_items=1)
        validate_sources(item.get("sources"), errors, f"{prefix}.sources")

        section = str(item.get("section") or "")
        normalized = normalize(section)
        if "polska" in normalized or "polityka" in normalized:
            poland_count += 1
        if "swiat" in normalized or "zagraniczne" in normalized:
            world_count += 1

    if len(value) >= MIN_ITEMS and poland_count < 2:
        errors.append("items must include at least 2 Poland/politics topics")
    if len(value) >= MIN_ITEMS and world_count < 2:
        errors.append("items must include at least 2 world topics")


def validate_sources(value: Any, errors: list[str], field_name: str) -> None:
    if not isinstance(value, list) or not value:
        errors.append(f"{field_name} must contain at least one item")
        return

    for index, source in enumerate(value):
        prefix = f"{field_name}[{index}]"
        if not isinstance(source, dict):
            errors.append(f"{prefix} must be an object")
            continue
        for field in ("title", "url"):
            if not non_empty_string(source.get(field)):
                errors.append(f"{prefix}.{field} must be a non-empty string")
        if "url" in source and not valid_url_string(source["url"]):
            errors.append(f"{prefix}.url must be an http(s) URL")


def validate_string_list(value: Any, field_name: str, errors: list[str], min_items: int) -> None:
    if not isinstance(value, list) or len(value) < min_items:
        errors.append(f"{field_name} must contain at least {min_items} item(s)")
        return
    if any(not non_empty_string(item) for item in value):
        errors.append(f"{field_name} must contain only non-empty strings")


def non_empty_string(value: Any) -> bool:
    return isinstance(value, str) and bool(value.strip())


def valid_url_string(value: Any) -> bool:
    return non_empty_string(value) and (value.startswith("https://") or value.startswith("http://"))


def normalize(value: str) -> str:
    replacements = str.maketrans("ąćęłńóśźżĄĆĘŁŃÓŚŹŻ", "acelnoszzACELNOSZZ")
    return value.translate(replacements).casefold()


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Validate Pavbot pulseNewsData JSON artifacts.")
    parser.add_argument("paths", nargs="+", type=Path, help="pulseNewsData JSON files to validate")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    failed = False
    for path in args.paths:
        errors = validate_file(path)
        for error in errors:
            print(f"invalid pulse news data: {path}: {error}", file=sys.stderr)
        failed = failed or bool(errors)
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
