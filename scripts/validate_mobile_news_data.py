#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any


TOPIC = "aktualne-wydarzenia-mobile"
REQUIRED_SECTION_TITLES = {"Ogólne", "Polska", "Polityka", "Sprawy zagraniczne", "Technologia"}
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

    for field in ("runDate", "runTime", "status", "headline"):
        if field in payload and not non_empty_string(payload[field]):
            errors.append(f"{field} must be a non-empty string")

    validate_string_list(payload.get("leadParagraphs"), "leadParagraphs", errors, min_items=1)
    validate_sources(payload.get("checkedSources"), errors, "checkedSources")
    validate_sections(payload.get("sections"), errors)
    validate_audio_artifacts(payload.get("audioArtifacts"), errors)
    return errors


def validate_sections(value: Any, errors: list[str]) -> None:
    if not isinstance(value, list):
        errors.append("sections must be a list")
        return

    titles: set[str] = set()
    for section_index, section in enumerate(value):
        prefix = f"sections[{section_index}]"
        if not isinstance(section, dict):
            errors.append(f"{prefix} must be an object")
            continue

        for field in sorted(REQUIRED_SECTION_FIELDS):
            if field not in section:
                errors.append(f"{prefix} missing required field: {field}")

        section_title = section.get("title")
        if non_empty_string(section_title):
            titles.add(section_title)
        else:
            errors.append(f"{prefix}.title must be a non-empty string")

        for field in ("id", "summary"):
            if field in section and not non_empty_string(section[field]):
                errors.append(f"{prefix}.{field} must be a non-empty string")

        validate_articles(section.get("articles"), errors, prefix, expected_section=section_title)

    missing_titles = sorted(REQUIRED_SECTION_TITLES - titles)
    if missing_titles:
        errors.append(f"sections missing required title(s): {', '.join(missing_titles)}")


def validate_articles(value: Any, errors: list[str], section_prefix: str, expected_section: Any) -> None:
    if not isinstance(value, list):
        errors.append(f"{section_prefix}.articles must be a list")
        return
    if len(value) < 2:
        errors.append(f"{section_prefix}.articles must contain at least 2 items")

    for article_index, article in enumerate(value):
        prefix = f"{section_prefix}.articles[{article_index}]"
        if not isinstance(article, dict):
            errors.append(f"{prefix} must be an object")
            continue

        for field in sorted(REQUIRED_ARTICLE_FIELDS):
            if field not in article:
                errors.append(f"{prefix} missing required field: {field}")

        for field in ("id", "section", "title", "lead", "analysis", "whyItMatters", "ttsText", "priority"):
            if field in article and not non_empty_string(article[field]):
                if field == "ttsText":
                    errors.append(f"article[{article_index}].ttsText is required")
                else:
                    errors.append(f"{prefix}.{field} is required")

        if non_empty_string(expected_section) and article.get("section") != expected_section:
            errors.append(f"{prefix}.section must match parent section title")

        validate_string_list(article.get("facts"), f"{prefix}.facts", errors, min_items=1)
        validate_string_list(article.get("tags"), f"{prefix}.tags", errors, min_items=1)
        validate_sources(article.get("sources"), errors, f"{prefix}.sources")


def validate_audio_artifacts(value: Any, errors: list[str]) -> None:
    if value is None:
        return
    if not isinstance(value, list):
        errors.append("audioArtifacts must be a list")
        return
    for index, artifact in enumerate(value):
        prefix = f"audioArtifacts[{index}]"
        if not isinstance(artifact, dict):
            errors.append(f"{prefix} must be an object")
            continue
        for field in ("variant", "path"):
            if field in artifact and not non_empty_string(artifact[field]):
                errors.append(f"{prefix}.{field} must be a non-empty string")


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
