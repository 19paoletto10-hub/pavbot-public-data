#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import re
import unicodedata
from pathlib import Path
from typing import Any


TOPIC = "aktualne-wydarzenia-mobile"
REQUIRED_SECTION_TITLES = ["Ogólne", "Polska", "Polityka", "Sprawy zagraniczne", "Technologia"]
LINK_RE = re.compile(r"\[([^\]]+)\]\((https?://[^)]+)\)")
DATE_RE = re.compile(r"(?P<date>\d{4}-\d{2}-\d{2})(?:-(?P<time>\d{4}))?")


def render_mobile_news_data(markdown_path: Path, output_path: Path) -> dict[str, Any]:
    markdown = markdown_path.read_text(encoding="utf-8")
    payload = parse_report(markdown, markdown_path)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return payload


def parse_report(markdown: str, markdown_path: Path) -> dict[str, Any]:
    sections = markdown_sections(markdown)
    run_date, run_time = parse_run_date_time(markdown, markdown_path)
    stamp = f"{run_date}-{run_time.replace(':', '')}"
    checked_sources = extract_sources(
        sections.get("Zakres sprawdzonych źródeł", "")
        or sections.get("Źródła", "")
        or markdown
    )
    lead_paragraphs = parse_lead_paragraphs(sections.get("Podsumowanie", ""))
    mobile_sections = parse_gazeta(sections.get("Gazeta", ""), fallback_sources=checked_sources)
    headline = lead_paragraphs[0] if lead_paragraphs else first_article_title(mobile_sections)

    return {
        "schemaVersion": 1,
        "topic": TOPIC,
        "runDate": run_date,
        "runTime": run_time,
        "status": parse_metadata("Status", markdown) or "Material update",
        "headline": clean_sentence(headline) or "Aktualne wydarzenia",
        "leadParagraphs": lead_paragraphs or ["Wydanie zawiera aktualne informacje z Polski i świata."],
        "checkedSources": checked_sources,
        "sections": mobile_sections,
        "audioArtifacts": collect_audio_artifacts(markdown_path, stamp),
    }


def collect_audio_artifacts(markdown_path: Path, stamp: str) -> list[dict[str, str]]:
    topic_root = topic_root_for(markdown_path)
    variants_path = topic_root / "podcasts" / stamp / "tts_variants.json"
    if not variants_path.is_file():
        return []

    try:
        payload = json.loads(variants_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return []

    artifacts: list[dict[str, str]] = []
    for variant in payload.get("variants", []):
        if not isinstance(variant, dict) or variant.get("status") != "ok":
            continue
        variant_id = str(variant.get("id") or "").strip()
        output_file = str(variant.get("output_file") or "").strip()
        if not variant_id or not output_file:
            continue
        if not audio_output_exists(topic_root, output_file):
            continue
        artifacts.append({"variant": variant_id, "path": normalized_artifact_path(topic_root, output_file)})
    return artifacts


def topic_root_for(markdown_path: Path) -> Path:
    parts = markdown_path.resolve().parts
    if TOPIC in parts:
        index = parts.index(TOPIC)
        return Path(*parts[: index + 1])
    return markdown_path.parent.parent


def audio_output_exists(topic_root: Path, output_file: str) -> bool:
    return any(candidate.is_file() and candidate.stat().st_size > 0 for candidate in audio_output_candidates(topic_root, output_file))


def audio_output_candidates(topic_root: Path, output_file: str) -> list[Path]:
    raw_path = Path(output_file)
    candidates = [raw_path]
    if not raw_path.is_absolute():
        candidates.append(topic_root / raw_path)
        parts = raw_path.parts
        if TOPIC in parts:
            index = parts.index(TOPIC)
            candidates.append(topic_root.joinpath(*parts[index + 1 :]))
    return candidates


def normalized_artifact_path(topic_root: Path, output_file: str) -> str:
    raw_path = Path(output_file)
    if not raw_path.is_absolute():
        return output_file
    try:
        relative = raw_path.relative_to(topic_root.parent.parent)
        return relative.as_posix()
    except ValueError:
        return raw_path.as_posix()


def markdown_sections(markdown: str) -> dict[str, str]:
    result: dict[str, list[str]] = {}
    current: str | None = None
    for line in markdown.replace("\r\n", "\n").splitlines():
        if line.startswith("## "):
            current = line[3:].strip()
            result.setdefault(current, [])
        elif current is not None:
            result[current].append(line)
    return {title: "\n".join(lines).strip() for title, lines in result.items()}


def parse_gazeta(markdown: str, fallback_sources: list[dict[str, str]]) -> list[dict[str, Any]]:
    raw_sections = split_gazeta_sections(markdown)
    parsed_sections: list[dict[str, Any]] = []
    for title in REQUIRED_SECTION_TITLES:
        block = raw_sections.get(title, "")
        summary, article_blocks = split_section_articles(block)
        articles = [
            parse_article(article_title, article_body, section_title=title, index=index, fallback_sources=fallback_sources)
            for index, (article_title, article_body) in enumerate(article_blocks, start=1)
        ]
        parsed_sections.append(
            {
                "id": slugify(title),
                "title": title,
                "summary": summary or f"Sekcja {title} wymaga uzupełnienia w raporcie.",
                "articles": articles,
            }
        )
    return parsed_sections


def split_gazeta_sections(markdown: str) -> dict[str, str]:
    result: dict[str, list[str]] = {}
    current: str | None = None
    for line in markdown.splitlines():
        if line.startswith("### "):
            current = line[4:].strip()
            result.setdefault(current, [])
        elif current is not None:
            result[current].append(line)
    return {title: "\n".join(lines).strip() for title, lines in result.items()}


def split_section_articles(markdown: str) -> tuple[str, list[tuple[str, str]]]:
    intro = ""
    articles: list[tuple[str, list[str]]] = []
    current_title: str | None = None

    for raw_line in markdown.splitlines():
        line = raw_line.rstrip()
        if line.startswith("Wprowadzenie:"):
            intro = line.removeprefix("Wprowadzenie:").strip()
            continue
        if line.startswith("#### "):
            current_title = line[5:].strip()
            articles.append((current_title, []))
            continue
        if current_title is not None and articles:
            articles[-1][1].append(line)

    return intro, [(title, "\n".join(lines).strip()) for title, lines in articles]


def parse_article(
    title: str,
    markdown: str,
    section_title: str,
    index: int,
    fallback_sources: list[dict[str, str]],
) -> dict[str, Any]:
    fields = article_fields(markdown)
    lead = fields.get("Lead", "")
    facts = fields.get("Fakty", [])
    analysis = fields.get("Analiza", "")
    why = fields.get("Dlaczego to ważne", "")
    sources = extract_sources("\n".join(facts)) or fallback_sources[:1]
    clean_facts = [strip_markdown_links(item) for item in facts if strip_markdown_links(item)]

    return {
        "id": f"{slugify(section_title)}-{index}-{slugify(title)}",
        "section": section_title,
        "title": title,
        "lead": lead or title,
        "facts": clean_facts or [lead or title],
        "analysis": analysis or "Brak dodatkowej analizy w raporcie.",
        "whyItMatters": why or "Ten sygnał wymaga monitorowania w kolejnym wydaniu.",
        "sources": sources,
        "tags": [section_title],
        "ttsText": tts_text(lead, clean_facts, analysis, why),
        "priority": "High",
    }


def article_fields(markdown: str) -> dict[str, Any]:
    fields: dict[str, Any] = {"Fakty": []}
    current_list: str | None = None
    for raw_line in markdown.splitlines():
        line = raw_line.strip()
        if not line:
            continue
        if line.startswith("Lead:"):
            fields["Lead"] = line.removeprefix("Lead:").strip()
            current_list = None
        elif line == "Fakty:":
            current_list = "Fakty"
        elif line.startswith("Analiza:"):
            fields["Analiza"] = line.removeprefix("Analiza:").strip()
            current_list = None
        elif line.startswith("Dlaczego to ważne:"):
            fields["Dlaczego to ważne"] = line.removeprefix("Dlaczego to ważne:").strip()
            current_list = None
        elif current_list and line.startswith("- "):
            fields.setdefault(current_list, []).append(line[2:].strip())
        elif current_list and fields.get(current_list):
            fields[current_list][-1] = f"{fields[current_list][-1]} {line}"
    return fields


def parse_lead_paragraphs(markdown: str) -> list[str]:
    paragraphs: list[str] = []
    for raw in markdown.splitlines():
        line = raw.strip()
        if not line:
            continue
        if line.startswith("- "):
            line = line[2:].strip()
        if line:
            paragraphs.append(clean_sentence(strip_markdown_links(line)))
    return paragraphs[:3]


def extract_sources(markdown: str) -> list[dict[str, str]]:
    seen: set[str] = set()
    sources: list[dict[str, str]] = []
    for title, url in LINK_RE.findall(markdown):
        if url in seen:
            continue
        seen.add(url)
        sources.append({"title": strip_markdown_links(title).strip() or url, "url": url})
    return sources


def parse_run_date_time(markdown: str, markdown_path: Path) -> tuple[str, str]:
    created = parse_metadata("Created", markdown)
    if created:
        match = re.search(r"(?P<date>\d{4}-\d{2}-\d{2}).*?(?P<time>\d{2}:\d{2})", created)
        if match:
            return match.group("date"), match.group("time")

    date = parse_metadata("Date", markdown)
    path_date, path_time = parse_stamp(markdown_path.stem)
    return date or path_date or markdown_path.stem[:10], path_time or "00:00"


def parse_stamp(value: str) -> tuple[str | None, str | None]:
    match = DATE_RE.search(value)
    if not match:
        return None, None
    time = match.group("time")
    if time:
        time = f"{time[:2]}:{time[2:]}"
    return match.group("date"), time


def parse_metadata(name: str, markdown: str) -> str | None:
    pattern = rf"(?m)^\s*{re.escape(name)}\s*:\s*(.+?)\s*$"
    match = re.search(pattern, markdown)
    return match.group(1).strip() if match else None


def first_article_title(sections: list[dict[str, Any]]) -> str:
    for section in sections:
        articles = section.get("articles")
        if articles:
            return str(articles[0].get("title") or "")
    return ""


def tts_text(lead: str, facts: list[str], analysis: str, why: str) -> str:
    parts = [lead, *facts, analysis, why]
    return " ".join(clean_sentence(part) for part in parts if clean_sentence(part))


def strip_markdown_links(text: str) -> str:
    return LINK_RE.sub(lambda match: match.group(1), text).strip()


def clean_sentence(text: str) -> str:
    return re.sub(r"\s+", " ", text).strip()


def slugify(value: str) -> str:
    normalized = unicodedata.normalize("NFKD", value)
    ascii_value = normalized.encode("ascii", "ignore").decode("ascii")
    slug = re.sub(r"[^a-zA-Z0-9]+", "-", ascii_value.lower()).strip("-")
    return slug or "item"


def main() -> None:
    parser = argparse.ArgumentParser(description="Render Pavbot mobileNewsData JSON from an Aktualne Markdown report.")
    parser.add_argument("markdown_report", type=Path)
    parser.add_argument("json_output", type=Path)
    args = parser.parse_args()
    render_mobile_news_data(args.markdown_report, args.json_output)


if __name__ == "__main__":
    main()
