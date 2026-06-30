#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any


SUPPORTED_TOPICS = {"tech-news", "polska-swiat"}
STRICT_QUALITY_START_DATE = "2026-06-27"
REQUIRED_FIELDS = {
    "schemaVersion",
    "topic",
    "runDate",
    "runTime",
    "status",
    "leadParagraphs",
    "summaryBullets",
    "articles",
    "podcastTopics",
    "checkedSources",
}
REQUIRED_ARTICLE_FIELDS = {
    "id",
    "section",
    "title",
    "standfirst",
    "whatHappened",
    "whyItMatters",
    "deeperAnalysis",
    "contextPoints",
    "sources",
    "priority",
    "tags",
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

    topic = payload.get("topic")
    if topic not in SUPPORTED_TOPICS:
        errors.append("topic must be tech-news or polska-swiat")

    for field in ("runDate", "status"):
        if field in payload and not non_empty_string(payload[field]):
            errors.append(f"{field} must be a non-empty string")

    if "runTime" in payload and payload["runTime"] is not None and not non_empty_string(payload["runTime"]):
        errors.append("runTime must be null or a non-empty string")

    validate_string_list(payload.get("leadParagraphs"), "leadParagraphs", errors, min_items=1)
    validate_string_list(payload.get("summaryBullets"), "summaryBullets", errors, min_items=1)
    validate_checked_sources(payload.get("checkedSources"), errors, field_name="checkedSources")
    validate_podcast_topics(payload.get("podcastTopics"), errors)
    run_date = payload.get("runDate") if non_empty_string(payload.get("runDate")) else ""
    validate_articles(payload.get("articles"), errors, run_date=run_date)
    return errors


def validate_articles(value: Any, errors: list[str], run_date: str) -> None:
    if not isinstance(value, list) or not value:
        errors.append("articles must contain at least one item")
        return

    for index, article in enumerate(value):
        prefix = f"articles[{index}]"
        if not isinstance(article, dict):
            errors.append(f"{prefix} must be an object")
            continue

        for field in sorted(REQUIRED_ARTICLE_FIELDS):
            if field not in article:
                errors.append(f"{prefix} missing required field: {field}")

        for field in ("id", "section", "title", "standfirst", "whatHappened", "whyItMatters", "priority"):
            if field in article and not non_empty_string(article[field]):
                errors.append(f"{prefix}.{field} must be a non-empty string")

        validate_string_list(article.get("deeperAnalysis"), f"{prefix}.deeperAnalysis", errors, min_items=2)
        validate_string_list(article.get("contextPoints"), f"{prefix}.contextPoints", errors, min_items=2)
        validate_string_list(article.get("tags"), f"{prefix}.tags", errors, min_items=1)
        validate_checked_sources(article.get("sources"), errors, field_name=f"{prefix}.sources")
        validate_article_quality(article, prefix, errors, enforce_duplicate_rules=run_date >= STRICT_QUALITY_START_DATE)


def validate_article_quality(
    article: dict[str, Any],
    prefix: str,
    errors: list[str],
    enforce_duplicate_rules: bool,
) -> None:
    standfirst = article.get("standfirst")
    if non_empty_string(standfirst) and sentence_count(standfirst) > 2:
        errors.append(f"{prefix}.standfirst must contain at most 2 sentence(s)")

    references = [
        normalize_for_comparison(article.get("standfirst")),
        normalize_for_comparison(article.get("whatHappened")),
    ]
    context_points = article.get("contextPoints")
    if isinstance(context_points, list) and context_points:
        references.append(normalize_for_comparison(strip_context_label(context_points[0])))
    references = [value for value in references if value]

    if not enforce_duplicate_rules:
        return

    deeper = article.get("deeperAnalysis")
    if not isinstance(deeper, list):
        return
    normalized_paragraphs = [
        normalize_for_comparison(paragraph)
        for paragraph in deeper
        if normalize_for_comparison(paragraph)
    ]
    if len(set(normalized_paragraphs)) < len(normalized_paragraphs):
        errors.append(f"{prefix}.deeperAnalysis must contain distinct paragraphs")
    for index, paragraph in enumerate(deeper):
        normalized = normalize_for_comparison(paragraph)
        if normalized and normalized in references:
            errors.append(
                f"{prefix}.deeperAnalysis[{index}] must not duplicate standfirst, whatHappened, or first context point"
            )


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


def validate_podcast_topics(value: Any, errors: list[str]) -> None:
    if value is None:
        return
    if not isinstance(value, list):
        errors.append("podcastTopics must be a list")
        return
    for index, item in enumerate(value):
        prefix = f"podcastTopics[{index}]"
        if not isinstance(item, dict):
            errors.append(f"{prefix} must be an object")
            continue
        for field in ("priority", "title", "rationale", "sourcesLabel"):
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


def sentence_count(value: str) -> int:
    count = 0
    for index, character in enumerate(value):
        if character not in ".!?":
            continue
        next_character = value[index + 1] if index + 1 < len(value) else ""
        if not next_character or next_character.isspace():
            count += 1
    return count or (1 if value.strip() else 0)


def strip_context_label(value: Any) -> Any:
    if not isinstance(value, str):
        return value
    return re.sub(r"^\s*co\s+si[eę]\s+sta[lł]o\s*:\s*", "", value, flags=re.IGNORECASE)


def normalize_for_comparison(value: Any) -> str:
    if not isinstance(value, str):
        return ""
    replacements = str.maketrans("ąćęłńóśźżĄĆĘŁŃÓŚŹŻ", "acelnoszzACELNOSZZ")
    normalized = value.translate(replacements).casefold()
    normalized = re.sub(r"\s+", " ", normalized)
    normalized = re.sub(r"^[•\\-]\s*", "", normalized)
    return normalized.strip()


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Validate Pavbot researchData JSON artifacts.")
    parser.add_argument("paths", nargs="+", type=Path, help="researchData JSON files to validate")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    failed = False
    for path in args.paths:
        errors = validate_file(path)
        for error in errors:
            print(f"invalid research data: {path}: {error}", file=sys.stderr)
        failed = failed or bool(errors)
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
