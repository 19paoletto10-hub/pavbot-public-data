#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any


REQUIRED_FIELDS = {
    "schemaVersion",
    "status",
    "runDate",
    "runTime",
    "executiveSummary",
    "opportunities",
    "changes",
    "risks",
    "recommendedActions",
    "checkedSources",
}

REQUIRED_OPPORTUNITY_FIELDS = {
    "rank",
    "title",
    "company",
    "location",
    "workMode",
    "compensation",
    "seniority",
    "fitSummary",
    "whyInteresting",
    "uncertainty",
    "sourceURLs",
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

    for field in ("status", "runDate", "runTime", "executiveSummary"):
        if field in payload and not non_empty_string(payload[field]):
            errors.append(f"{field} must be a non-empty string")

    validate_string_list(payload, "changes", errors)
    validate_string_list(payload, "risks", errors)
    validate_string_list(payload, "recommendedActions", errors)
    validate_checked_sources(payload.get("checkedSources"), errors)
    validate_opportunities(payload.get("opportunities"), errors)
    return errors


def validate_opportunities(value: Any, errors: list[str]) -> None:
    if not isinstance(value, list) or not value:
        errors.append("opportunities must contain at least one item")
        return

    for index, opportunity in enumerate(value):
        prefix = f"opportunities[{index}]"
        if not isinstance(opportunity, dict):
            errors.append(f"{prefix} must be an object")
            continue

        for field in sorted(REQUIRED_OPPORTUNITY_FIELDS):
            if field not in opportunity:
                errors.append(f"{prefix} missing required field: {field}")

        if "rank" in opportunity and not isinstance(opportunity["rank"], int):
            errors.append(f"{prefix}.rank must be an integer")

        for field in (
            "title",
            "company",
            "location",
            "workMode",
            "compensation",
            "seniority",
            "fitSummary",
            "whyInteresting",
            "uncertainty",
        ):
            if field in opportunity and not non_empty_string(opportunity[field]):
                errors.append(f"{prefix}.{field} must be a non-empty string")

        source_urls = opportunity.get("sourceURLs")
        if not isinstance(source_urls, list) or not source_urls:
            errors.append(f"{prefix}.sourceURLs must contain at least one URL")
        else:
            for url_index, url in enumerate(source_urls):
                if not valid_url_string(url):
                    errors.append(f"{prefix}.sourceURLs[{url_index}] must be an http(s) URL")

        tags = opportunity.get("tags")
        if not isinstance(tags, list):
            errors.append(f"{prefix}.tags must be a list")
        elif any(not non_empty_string(tag) for tag in tags):
            errors.append(f"{prefix}.tags must contain only non-empty strings")


def validate_checked_sources(value: Any, errors: list[str]) -> None:
    if not isinstance(value, list) or not value:
        errors.append("checkedSources must contain at least one item")
        return

    for index, source in enumerate(value):
        prefix = f"checkedSources[{index}]"
        if not isinstance(source, dict):
            errors.append(f"{prefix} must be an object")
            continue
        for field in ("title", "url"):
            if not non_empty_string(source.get(field)):
                errors.append(f"{prefix}.{field} must be a non-empty string")
        if "url" in source and not valid_url_string(source["url"]):
            errors.append(f"{prefix}.url must be an http(s) URL")


def validate_string_list(payload: dict[str, Any], field: str, errors: list[str]) -> None:
    if field not in payload:
        return
    value = payload[field]
    if not isinstance(value, list):
        errors.append(f"{field} must be a list")
        return
    if any(not non_empty_string(item) for item in value):
        errors.append(f"{field} must contain only non-empty strings")


def non_empty_string(value: Any) -> bool:
    return isinstance(value, str) and bool(value.strip())


def valid_url_string(value: Any) -> bool:
    if not non_empty_string(value):
        return False
    return value.startswith("https://") or value.startswith("http://")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Validate Pavbot LLM/AI jobs data JSON artifacts.")
    parser.add_argument("paths", nargs="+", type=Path, help="jobs.json files to validate")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    failed = False
    for path in args.paths:
        errors = validate_file(path)
        for error in errors:
            print(f"invalid jobs data: {path}: {error}", file=sys.stderr)
        failed = failed or bool(errors)
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
