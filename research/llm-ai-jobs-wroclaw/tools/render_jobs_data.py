#!/usr/bin/env python3
"""Render an LLM/AI jobs Markdown report into Pavbot jobsData JSON."""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path
from typing import Any


DATE_RE = re.compile(r"^Date:\s*(?P<date>\d{4}-\d{2}-\d{2})\s+(?P<time>\d{2}:\d{2})", re.MULTILINE)
STATUS_RE = re.compile(r"^Status:\s*(?P<status>.+)$", re.MULTILINE)
LINK_RE = re.compile(r"\[([^\]]+)\]\((https?://[^)]+)\)")
RANK_RE = re.compile(r"^(?P<rank>\d+)\.\s*")

SUMMARY_HEADINGS = [
    "Podsumowanie zarządcze",
    "Podsumowanie wykonawcze",
    "Executive Summary",
    "Summary",
]
OPPORTUNITY_HEADINGS = [
    "Najciekawsze nowe lub materialnie zmienione role",
    "Najciekawsze nowe lub zmienione role",
    "Top New Or Materially Changed Roles",
    "Top New Roles",
    "Top Roles",
]
SCOPE_HEADINGS = ["Zakres sprawdzony", "Scope Checked"]
CHANGES_HEADINGS = ["Zmiany od poprzedniej rundy", "Changes Since Previous Run"]
RISKS_HEADINGS = ["Ryzyka i niepewności", "Ryzyka i niepewność", "Risks"]
ACTIONS_HEADINGS = ["Rekomendowane akcje", "Rekomendowane działania", "Recommended Actions"]


def render_jobs_data(markdown_path: Path, output_path: Path) -> None:
    report = parse_report(markdown_path.read_text(encoding="utf-8"))
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def parse_report(markdown: str) -> dict[str, Any]:
    date_match = DATE_RE.search(markdown)
    if not date_match:
        raise ValueError("missing Date line with YYYY-MM-DD HH:MM")

    status_match = STATUS_RE.search(markdown)
    summary = clean_block(section(markdown, SUMMARY_HEADINGS))
    opportunities = parse_opportunities(
        section(markdown, OPPORTUNITY_HEADINGS),
        fallback_urls=[source["url"] for source in parse_checked_sources(section(markdown, SCOPE_HEADINGS))],
    )
    if not opportunities:
        raise ValueError("missing job opportunities section")

    return {
        "schemaVersion": 1,
        "status": clean_inline(status_match.group("status")) if status_match else "Unknown",
        "runDate": date_match.group("date"),
        "runTime": date_match.group("time"),
        "executiveSummary": summary or "Brak podsumowania w raporcie.",
        "opportunities": opportunities,
        "changes": bullet_items(section(markdown, CHANGES_HEADINGS)),
        "risks": bullet_items(section(markdown, RISKS_HEADINGS)),
        "recommendedActions": bullet_items(section(markdown, ACTIONS_HEADINGS)),
        "checkedSources": parse_checked_sources(section(markdown, SCOPE_HEADINGS)),
    }


def section(markdown: str, headings: list[str]) -> str:
    normalized_headings = {normalize_heading(heading) for heading in headings}
    lines = markdown.splitlines()
    found = False
    result: list[str] = []

    for line in lines:
        stripped = line.strip()
        if stripped.startswith("## "):
            if found:
                break
            heading = normalize_heading(stripped[3:])
            found = heading in normalized_headings
            continue
        if found:
            result.append(line)

    return "\n".join(result)


def parse_opportunities(markdown: str, fallback_urls: list[str]) -> list[dict[str, Any]]:
    opportunities: list[dict[str, Any]] = []
    current_heading: str | None = None
    current_block: list[str] = []

    def flush() -> None:
        nonlocal current_heading, current_block
        if not current_heading:
            return
        opportunities.append(
            parse_opportunity(
                current_heading,
                "\n".join(current_block),
                rank_fallback=len(opportunities) + 1,
                fallback_urls=fallback_urls,
            )
        )

    for line in markdown.splitlines():
        stripped = line.strip()
        if stripped.startswith("### "):
            flush()
            current_heading = stripped[4:]
            current_block = []
        elif current_heading:
            current_block.append(line)
    flush()

    if opportunities:
        return opportunities

    for rank, block in enumerate(flat_bullet_blocks(markdown), start=1):
        opportunities.append(
            parse_flat_opportunity(
                block,
                rank_fallback=rank,
                fallback_urls=fallback_urls,
            )
        )

    return opportunities


def parse_opportunity(heading: str, block: str, rank_fallback: int, fallback_urls: list[str]) -> dict[str, Any]:
    heading = clean_inline(heading)
    rank_match = RANK_RE.match(heading)
    rank = int(rank_match.group("rank")) if rank_match else rank_fallback
    heading_without_rank = RANK_RE.sub("", heading).strip()
    company, title = split_company_title(heading_without_rank)
    source_urls = [url for _, url in markdown_links(block)] or fallback_urls[:1]
    location = bullet_value(block, ["Lokalizacja/remote", "Lokalizacja", "Location", "Location/remote"])
    fit_summary = bullet_value(block, ["Fit LLM/AI", "Fit"])
    why_interesting = bullet_value(block, ["Dlaczego interesujące", "Why interesting", "Why it matters"])
    uncertainty = bullet_value(block, ["Niepewność", "Uncertainty"])
    compensation = bullet_value(block, ["Wynagrodzenie", "Compensation"], fallback="Brak publicznych widełek.")

    search_text = " ".join([title, company, location, fit_summary, why_interesting])
    return {
        "rank": rank,
        "title": title,
        "company": company,
        "location": location,
        "workMode": infer_work_mode(location),
        "compensation": compensation,
        "seniority": infer_seniority(title),
        "fitSummary": fit_summary,
        "whyInteresting": why_interesting,
        "uncertainty": uncertainty,
        "sourceURLs": source_urls,
        "tags": infer_tags(search_text),
    }


def parse_flat_opportunity(block: str, rank_fallback: int, fallback_urls: list[str]) -> dict[str, Any]:
    raw = block.strip()
    if raw.startswith("- "):
        raw = raw[2:].strip()

    links = markdown_links(raw)
    label = clean_inline(links[0][0]) if links else ""
    heading_without_rank = label.strip() or "Nieznana firma - Nieznany tytuł"
    company, title = split_company_title(heading_without_rank)
    source_urls = [url for _, url in links] or fallback_urls[:1]
    without_lead = raw
    if links:
        first_link = f"[{links[0][0]}]({links[0][1]})"
        without_lead = raw.replace(first_link, "", 1).lstrip(" :")
    normalized = clean_inline(without_lead)
    clauses = [clean_inline(part).strip(" .") for part in re.split(r";\s*", normalized) if clean_inline(part).strip(" .")]
    backticked = re.findall(r"`([^`]+)`", block)

    location = infer_flat_location(backticked, clauses)
    compensation = infer_flat_compensation(backticked, clauses)
    uncertainty = infer_flat_uncertainty(clauses)
    fit_summary = infer_flat_fit_summary(clauses)
    why_interesting = infer_flat_why_interesting(clauses, fit_summary)

    search_text = " ".join([title, company, location, fit_summary, why_interesting, normalized])
    return {
        "rank": rank_fallback,
        "title": title,
        "company": company,
        "location": location,
        "workMode": infer_work_mode(location),
        "compensation": compensation,
        "seniority": infer_seniority(title),
        "fitSummary": fit_summary,
        "whyInteresting": why_interesting,
        "uncertainty": uncertainty,
        "sourceURLs": source_urls,
        "tags": infer_tags(search_text),
    }


def split_company_title(value: str) -> tuple[str, str]:
    if " - " not in value:
        return "Nieznana firma", value.strip()
    company, title = value.split(" - ", 1)
    return company.strip(), title.strip()


def flat_bullet_blocks(markdown: str) -> list[str]:
    blocks: list[str] = []
    current: list[str] = []
    for line in markdown.splitlines():
        stripped = line.strip()
        if stripped.startswith("- "):
            if current:
                blocks.append(" ".join(current))
            current = [stripped]
        elif current and stripped and not stripped.startswith("#"):
            current.append(stripped)
        elif current:
            blocks.append(" ".join(current))
            current = []
    if current:
        blocks.append(" ".join(current))
    return [block for block in blocks if markdown_links(block)]


def bullet_value(block: str, labels: list[str], fallback: str = "Brak danych w raporcie.") -> str:
    normalized_labels = {normalize_label(label) for label in labels}
    for line in block.splitlines():
        stripped = line.strip()
        if not stripped.startswith("- "):
            continue
        body = stripped[2:]
        if ":" not in body:
            continue
        label, value = body.split(":", 1)
        if normalize_label(label) in normalized_labels:
            return clean_inline(value).strip() or fallback
    return fallback


def infer_flat_location(backticked: list[str], clauses: list[str]) -> str:
    location_parts: list[str] = []
    for value in backticked:
        lowered = value.casefold()
        if any(token in lowered for token in ("wroc", "remote", "zdal", "hybrid", "hybryd", "location")):
            location_parts.append(value)
    if location_parts:
        return ", ".join(dict.fromkeys(location_parts))
    if clauses:
        return clauses[0] if len(clauses[0]) < 120 else "Brak danych w raporcie."
    return "Brak danych w raporcie."


def infer_flat_compensation(backticked: list[str], clauses: list[str]) -> str:
    money_re = re.compile(r"\b(?:PLN|USD|EUR|CHF|zł|zl|net|gross|brutto|netto)\b", re.IGNORECASE)
    for value in backticked:
        if money_re.search(value):
            return value
    for clause in clauses:
        if money_re.search(clause):
            return clause
    return "Brak publicznych widełek."


def infer_flat_uncertainty(clauses: list[str]) -> str:
    for clause in clauses:
        lowered = clause.casefold()
        if "niepewność" in lowered or "uncertainty" in lowered:
            return clause
    return "Brak danych w raporcie."


def infer_flat_fit_summary(clauses: list[str]) -> str:
    descriptive = [
        clause
        for clause in clauses
        if "niepewność" not in clause.casefold() and "uncertainty" not in clause.casefold()
    ]
    if len(descriptive) >= 2:
        return descriptive[1]
    if descriptive:
        return descriptive[0]
    return "Brak danych w raporcie."


def infer_flat_why_interesting(clauses: list[str], fit_summary: str) -> str:
    descriptive = [
        clause
        for clause in clauses
        if "niepewność" not in clause.casefold() and "uncertainty" not in clause.casefold()
    ]
    if len(descriptive) >= 3:
        return descriptive[2]
    if len(descriptive) >= 2:
        return descriptive[1]
    if descriptive:
        return descriptive[0]
    return fit_summary or "Brak danych w raporcie."


def parse_checked_sources(markdown: str) -> list[dict[str, str]]:
    sources: list[dict[str, str]] = []
    seen_urls: set[str] = set()
    for line in markdown.splitlines():
        for title, url in markdown_links(line):
            if url in seen_urls:
                continue
            seen_urls.add(url)
            sources.append({"title": title, "url": url, "status": infer_source_status(line)})
    return sources


def infer_source_status(line: str) -> str:
    lowered = line.casefold()
    if "no material change" in lowered or "bez materialnej zmiany" in lowered:
        return "checked-no-material-change"
    if "excluded" in lowered or "inactive" in lowered or "nieaktyw" in lowered:
        return "checked-inactive"
    return "checked"


def bullet_items(markdown: str) -> list[str]:
    return [
        clean_inline(line.strip()[2:]).strip()
        for line in markdown.splitlines()
        if line.strip().startswith("- ") and clean_inline(line.strip()[2:]).strip()
    ]


def markdown_links(markdown: str) -> list[tuple[str, str]]:
    return [(match.group(1), match.group(2)) for match in LINK_RE.finditer(markdown)]


def infer_work_mode(location: str) -> str:
    lowered = location.casefold()
    if "remote" in lowered or "zdal" in lowered:
        return "Remote"
    if "hybrid" in lowered or "hybryd" in lowered:
        return "Hybrid"
    if "wrocław" in lowered or "wroclaw" in lowered:
        return "Wrocław"
    return location or "Brak danych"


def infer_seniority(title: str) -> str:
    lowered = title.casefold()
    for label in ("Principal", "Staff", "Senior", "Lead", "Mid", "Junior"):
        if label.casefold() in lowered:
            return label
    return "Nieokreślony"


def infer_tags(text: str) -> list[str]:
    lowered = text.casefold()
    tags: list[str] = []
    for label, needle in [
        ("Agentic AI", "agentic"),
        ("RAG", "rag"),
        ("LLM", "llm"),
        ("GenAI", "genai"),
        ("MLOps", "mlops"),
        ("LLMOps", "llmops"),
        ("Python", "python"),
        ("AWS", "aws"),
        ("Azure", "azure"),
        ("GCP", "gcp"),
    ]:
        if needle in lowered and label not in tags:
            tags.append(label)
    return tags


def clean_block(markdown: str) -> str:
    return " ".join(
        clean_inline(line).strip()
        for line in markdown.splitlines()
        if clean_inline(line).strip()
    )


def clean_inline(value: str) -> str:
    value = re.sub(r"\[([^\]]+)\]\((https?://[^)]+)\)", r"\1", value)
    return value.replace("`", "").replace("**", "").replace("__", "").strip()


def normalize_heading(value: str) -> str:
    return re.sub(r"\s+", " ", clean_inline(value)).casefold()


def normalize_label(value: str) -> str:
    value = re.sub(r"\s*/\s*", "/", clean_inline(value))
    return re.sub(r"\s+", " ", value).strip().casefold()


def default_output_path(markdown_path: Path) -> Path:
    return markdown_path.parents[1] / "data" / f"{markdown_path.stem}-jobs.json"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("markdown_report", type=Path)
    parser.add_argument("json_output", nargs="?", type=Path)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    output = args.json_output or default_output_path(args.markdown_report)
    render_jobs_data(args.markdown_report, output)
    print(f"jobs data written: {output}")


if __name__ == "__main__":
    main()
