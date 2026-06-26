#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any


TOPIC = "aktualne-wydarzenia-mobile"
REQUIRED_FIELDS = {
    "schemaVersion",
    "topic",
    "runDate",
    "runTime",
    "status",
    "headline",
    "leadParagraphs",
    "sections",
    "checkedSources",
    "audioArtifacts",
}
REQUIRED_SECTION_FIELDS = {"id", "title", "summary", "articles"}
REQUIRED_ARTICLE_FIELDS = {
    "id",
    "section",
    "title",
    "lead",
    "facts",
    "analysis",
    "whyItMatters",
    "sources",
    "tags",
    "ttsText",
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

    for field in ("runDate", "status", "headline"):
        if field in payload and not non_empty_string(payload[field]):
            errors.append(f"{field} must be a non-empty string")
    if "runTime" in payload and payload["runTime"] is not None and not non_empty_string(payload["runTime"]):
        errors.append("runTime must be null or a non-empty string")

    validate_string_list(payload.get("leadParagraphs"), "leadParagraphs", errors, min_items=1)
    validate_checked_sources(payload.get("checkedSources"), errors, "checkedSources")
    validate_audio_artifacts(payload.get("audioArtifacts"), errors)
    validate_sections(payload.get("sections"), errors)
    return errors


def validate_sections(value: Any, errors: list[str]) -> None:
    if not isinstance(value, list) or not value:
        errors.append("sections must contain at least one item")
        return

    for index, section in enumerate(value):
        prefix = f"sections[{index}]"
        if not isinstance(section, dict):
            errors.append(f"{prefix} must be an object")
            continue
        for field in sorted(REQUIRED_SECTION_FIELDS):
            if field not in section:
                errors.append(f"{prefix} missing required field: {field}")
        for field in ("id", "title", "summary"):
            if field in section and not non_empty_string(section[field]):
                errors.append(f"{prefix}.{field} must be a non-empty string")
        validate_articles(section.get("articles"), errors, section_prefix=prefix)


def validate_articles(value: Any, errors: list[str], section_prefix: str) -> None:
    if not isinstance(value, list) or not value:
        errors.append(f"{section_prefix}.articles must contain at least one item")
        return

    for index, article in enumerate(value):
        prefix = f"{section_prefix}.article[{index}]"
        if not isinstance(article, dict):
            errors.append(f"{prefix} must be an object")
            continue
        for field in sorted(REQUIRED_ARTICLE_FIELDS):
            if field not in article:
                errors.append(f"{prefix} missing required field: {field}")
        for field in ("id", "section", "title", "lead", "analysis", "whyItMatters", "ttsText", "priority"):
            if field in article and not non_empty_string(article[field]):
                errors.append(f"article[{index}].{field} is required")
        validate_string_list(article.get("facts"), f"article[{index}].facts", errors, min_items=1)
        validate_string_list(article.get("tags"), f"article[{index}].tags", errors, min_items=1)
        validate_checked_sources(article.get("sources"), errors, f"article[{index}].sources")
        if non_empty_string(article.get("ttsText")) and contains_url(article["ttsText"]):
            errors.append(f"article[{index}].ttsText must not contain URLs")


def validate_checked_sources(value: Any, errors: list[str], field_name: str) -> None:
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


def validate_audio_artifacts(value: Any, errors: list[str]) -> None:
    if value is None:
        return
    if not isinstance(value, list):
        errors.append("audioArtifacts must be a list")
        return
    for index, item in enumerate(value):
        prefix = f"audioArtifacts[{index}]"
        if not isinstance(item, dict):
            errors.append(f"{prefix} must be an object")
            continue
        for field in ("variant", "path"):
            if field in item and not isinstance(item[field], str):
                errors.append(f"{prefix}.{field} must be a string")


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


def contains_url(value: str) -> bool:
    return "http://" in value or "https://" in value


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Validate Pavbot mobileNewsData JSON artifacts.")
    parser.add_argument("paths", nargs="+", type=Path, help="mobileNewsData JSON files to validate")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    failed = False
    for path in args.paths:
        errors = validate_file(path)
        for error in errors:
            print(f"invalid mobile news data: {path}: {error}", file=sys.stderr)
        failed = failed or bool(errors)
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
