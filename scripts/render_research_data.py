#!/usr/bin/env python3
"""Render Pavbot research Markdown into structured researchData JSON."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
from pathlib import Path
from typing import Any


SUPPORTED_TOPICS = {"tech-news", "polska-swiat"}
DATE_RE = re.compile(r"(?P<date>\d{4}-\d{2}-\d{2})(?:[-\s](?P<time>\d{2}:?\d{2}))?")
STATUS_RE = re.compile(r"^Status:\s*(?P<status>.+)$", re.MULTILINE)
LINK_RE = re.compile(r"\[([^\]]+)\]\((https?://[^)]+)\)")

SUMMARY_HEADINGS = ["Podsumowanie", "Summary", "Executive Summary"]
FACT_HEADINGS = ["Nowe fakty", "New facts", "Key facts", "Najważniejsze fakty"]
SOURCE_HEADINGS = ["Źródła", "Sources", "Source", "Zakres sprawdzony", "Scope Checked"]
PODCAST_HEADINGS = ["Tematy do podcastu", "Podcast topics"]
APP_ARTICLE_HEADINGS = ["Artykuły do aplikacji", "Artykuly do aplikacji", "App articles"]
REQUIRED_APP_ARTICLE_FIELDS = {
    "section": "Sekcja",
    "priority": "Priorytet",
    "tags": "Tagi",
    "standfirst": "Standfirst",
    "whatHappened": "Co się stało",
    "whyItMatters": "Dlaczego ważne",
    "deeperAnalysis": "Pełny opis",
    "contextPoints": "Kontekst",
    "sources": "Źródła",
}

TECH_SECTIONS = {
    "Cyber": ["cve", "cyber", "security", "malware", "phishing", "vulnerability", "bezpieczeństwo cyfrowe"],
    "Infrastruktura": ["chip", "compute", "gpu", "tpu", "inference", "data center", "broadcom", "qualcomm", "micron", "infrastr"],
    "Regulacje": ["regul", "senate", "cma", "act", "law", "ustaw", "compliance"],
    "Produkty": ["product", "produkt", "app", "cloudflare", "oauth", "figma", "wallet", "deezer", "krea", "apple"],
    "AI": ["ai", "llm", "openai", "anthropic", "model", "agent", "rag", "genai"],
}

POLSKA_SECTIONS = {
    "Pogoda": ["pogod", "upał", "burz", "imgw", "rcb"],
    "Bezpieczeństwo": ["bezpieczen", "bezpieczeń", "nato", "mon", "wojsk", "obron", "granica", "iran", "ukraina"],
    "Gospodarka": ["gospod", "energia", "firm", "biznes", "inflac", "bank", "podat"],
    "Polityka": ["sejm", "rząd", "rzad", "prezydent", "premier", "wybor", "polity"],
    "Świat": ["usa", "europa", "guardian", "ap", "turcja", "chiny", "świat", "swiat"],
    "Polska": ["polsk", "kprm", "warszaw", "gdańsk", "gdansk", "wrocław", "wroclaw"],
}

TECH_TAGS = ["AI", "LLM", "RAG", "OpenAI", "Cloudflare", "NVIDIA", "Cyber", "Regulacje", "Infrastruktura"]
POLSKA_TAGS = ["Polska", "UE", "NATO", "Ukraina", "Bezpieczeństwo", "Gospodarka", "Polityka", "Pogoda"]


def render_research_data(
    markdown_path: Path,
    output_path: Path,
    topic: str | None = None,
    require_app_articles: bool = False,
) -> dict[str, Any]:
    topic = topic or infer_topic(markdown_path)
    if topic not in SUPPORTED_TOPICS:
        raise ValueError(f"unsupported researchData topic: {topic}")

    payload = parse_report(
        markdown_path.read_text(encoding="utf-8"),
        markdown_path=markdown_path,
        topic=topic,
        require_app_articles=require_app_articles,
    )
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return payload


def parse_report(markdown: str, markdown_path: Path, topic: str, require_app_articles: bool = False) -> dict[str, Any]:
    sections = markdown_sections(markdown)
    lead_paragraphs = clean_paragraphs(section(sections, SUMMARY_HEADINGS))
    facts = section(sections, FACT_HEADINGS)
    app_articles = section(sections, APP_ARTICLE_HEADINGS)
    if require_app_articles:
        validate_required_app_articles(app_articles)
    source_text = section(sections, SOURCE_HEADINGS)
    checked_sources = extract_sources(source_text) or extract_sources(markdown)
    articles = parse_app_articles(app_articles, topic=topic, package_key=markdown_path.stem, fallback_sources=checked_sources)
    if not articles:
        articles = parse_articles(facts, topic=topic, package_key=markdown_path.stem, fallback_sources=checked_sources)
    if not articles and lead_paragraphs:
        articles = fallback_articles(lead_paragraphs, topic=topic, package_key=markdown_path.stem, fallback_sources=checked_sources)

    run_date, run_time = parse_run_date_time(markdown, markdown_path)
    lead = lead_paragraphs or ["Raport jest gotowy do czytania w aplikacji Pavbot."]
    summary_bullets = build_summary_bullets(lead, articles, topic)

    return {
        "schemaVersion": 1,
        "topic": topic,
        "runDate": run_date,
        "runTime": run_time,
        "status": parse_status(markdown),
        "leadParagraphs": lead,
        "summaryBullets": summary_bullets,
        "articles": articles,
        "podcastTopics": parse_podcast_topics(section(sections, PODCAST_HEADINGS)),
        "checkedSources": checked_sources,
    }


def markdown_sections(markdown: str) -> dict[str, str]:
    result: dict[str, list[str]] = {}
    current_title: str | None = None
    for line in markdown.replace("\r\n", "\n").splitlines():
        stripped = line.strip()
        if stripped.startswith("## "):
            current_title = normalize_heading(stripped[3:])
            result.setdefault(current_title, [])
            continue
        if current_title:
            result[current_title].append(line)
    return {title: "\n".join(lines) for title, lines in result.items()}


def section(sections: dict[str, str], headings: list[str]) -> str:
    wanted = [normalize_heading(heading) for heading in headings]
    for title, body in sections.items():
        if any(needle in title for needle in wanted):
            return body
    return ""


def validate_required_app_articles(markdown: str) -> None:
    if not markdown.strip():
        raise ValueError("missing required section: Artykuły do aplikacji")

    blocks = app_article_blocks(markdown)
    if not blocks:
        raise ValueError("Artykuły do aplikacji must contain at least one ### article")

    errors: list[str] = []
    for title, block in blocks:
        fields = app_article_fields(block)
        missing = [
            display
            for field, display in REQUIRED_APP_ARTICLE_FIELDS.items()
            if not app_field_has_content(fields, field)
        ]
        quality_errors: list[str] = []
        if len(field_paragraphs(fields, "deeperAnalysis")) < 2:
            quality_errors.append("Pełny opis must contain at least 2 paragraphs")
        if len(field_list(fields, "contextPoints")) < 2:
            quality_errors.append("Kontekst must contain at least 2 points")

        if missing or quality_errors:
            details = []
            if missing:
                details.append("missing " + ", ".join(missing))
            details.extend(quality_errors)
            errors.append(f"incomplete app article '{clean_text(title)}': {'; '.join(details)}")

    if errors:
        raise ValueError("; ".join(errors))


def app_field_has_content(fields: dict[str, list[str]], field: str) -> bool:
    if field == "tags":
        return bool(split_tags(field_text(fields, field)))
    if field == "deeperAnalysis":
        return bool(field_paragraphs(fields, field))
    if field == "contextPoints":
        return bool(field_list(fields, field))
    if field == "sources":
        return bool(extract_sources("\n".join(fields.get(field, []))))
    return bool(field_text(fields, field))


def parse_articles(facts: str, topic: str, package_key: str, fallback_sources: list[dict[str, str]]) -> list[dict[str, Any]]:
    blocks = bullet_blocks(facts)
    if not blocks:
        blocks = heading_blocks(facts)

    articles: list[dict[str, Any]] = []
    for index, block in enumerate(blocks):
        body = clean_text(block)
        if not body:
            continue
        section_name = classify_section(block, topic)
        sources = extract_sources(block) or fallback_sources[:1]
        title = article_title(body, section_name, topic, sources)
        standfirst = first_sentences(body, max_count=2)
        what_happened = build_what_happened(body)
        why_it_matters = build_why_it_matters(section_name, topic, body)
        deeper = build_deeper_analysis(body, section_name, topic, sources)
        context_points = build_context_points(body, section_name, topic)
        article = {
            "id": stable_id(topic, package_key, index, title),
            "section": section_name,
            "title": title,
            "standfirst": standfirst,
            "whatHappened": what_happened,
            "whyItMatters": why_it_matters,
            "deeperAnalysis": deeper,
            "contextPoints": context_points,
            "sources": sources,
            "priority": priority_from_text(block, index),
            "tags": tags_for(topic, section_name, body),
        }
        articles.append(article)
    return articles


APP_FIELD_LABELS = {
    "sekcja": "section",
    "section": "section",
    "priorytet": "priority",
    "priority": "priority",
    "tagi": "tags",
    "tags": "tags",
    "standfirst": "standfirst",
    "lead": "standfirst",
    "co sie stalo": "whatHappened",
    "what happened": "whatHappened",
    "dlaczego wazne": "whyItMatters",
    "why it matters": "whyItMatters",
    "pelny opis": "deeperAnalysis",
    "pełny opis": "deeperAnalysis",
    "glebsza analiza": "deeperAnalysis",
    "głębsza analiza": "deeperAnalysis",
    "deeper analysis": "deeperAnalysis",
    "kontekst": "contextPoints",
    "context": "contextPoints",
    "zrodla": "sources",
    "źródła": "sources",
    "sources": "sources",
}


def parse_app_articles(
    markdown: str,
    topic: str,
    package_key: str,
    fallback_sources: list[dict[str, str]],
) -> list[dict[str, Any]]:
    articles: list[dict[str, Any]] = []
    for index, (title, block) in enumerate(app_article_blocks(markdown)):
        fields = app_article_fields(block)
        body = clean_text(" ".join([title, block]))
        if not body:
            continue

        standfirst = field_text(fields, "standfirst") or first_sentences(body, max_count=2)
        what_happened = field_text(fields, "whatHappened") or build_what_happened(standfirst)
        section_name = field_text(fields, "section") or classify_section(body, topic)
        why_it_matters = field_text(fields, "whyItMatters") or build_why_it_matters(section_name, topic, body)
        deeper = field_paragraphs(fields, "deeperAnalysis")
        if not deeper:
            deeper = build_deeper_analysis(body, section_name, topic, fallback_sources[:1])
        context_points = field_list(fields, "contextPoints")
        if len(context_points) < 2:
            context_points = build_context_points(body, section_name, topic)
        sources = extract_sources("\n".join(fields.get("sources", []))) or extract_sources(block) or fallback_sources[:1]
        priority = field_text(fields, "priority") or priority_from_text(block, index)
        explicit_tags = split_tags(field_text(fields, "tags"))
        tags = explicit_tags or tags_for(topic, section_name, body)

        articles.append(
            {
                "id": stable_id(topic, package_key, index, title),
                "section": section_name,
                "title": clean_text(title) or article_title(body, section_name, topic, sources),
                "standfirst": standfirst,
                "whatHappened": what_happened,
                "whyItMatters": why_it_matters,
                "deeperAnalysis": dedupe_strings(deeper)[:5],
                "contextPoints": dedupe_strings(context_points)[:5],
                "sources": sources,
                "priority": priority,
                "tags": tags[:6],
            }
        )
    return articles


def app_article_blocks(markdown: str) -> list[tuple[str, str]]:
    blocks: list[tuple[str, str]] = []
    current_title: str | None = None
    current_lines: list[str] = []

    def flush() -> None:
        nonlocal current_title, current_lines
        if current_title and clean_text("\n".join(current_lines)):
            blocks.append((clean_text(current_title), "\n".join(current_lines).strip()))
        current_title = None
        current_lines = []

    for raw_line in markdown.replace("\r\n", "\n").splitlines():
        line = raw_line.strip()
        if line.startswith("### "):
            flush()
            current_title = line[4:].strip()
            continue
        if current_title:
            current_lines.append(raw_line)
    flush()
    return blocks


def app_article_fields(block: str) -> dict[str, list[str]]:
    fields: dict[str, list[str]] = {}
    current: str | None = None
    label_re = re.compile(r"^([^:]{2,40}):\s*(.*)$")

    for raw_line in block.replace("\r\n", "\n").splitlines():
        stripped = raw_line.strip()
        match = label_re.match(stripped)
        label = normalize_text(match.group(1)) if match else ""
        if match and label in APP_FIELD_LABELS:
            current = APP_FIELD_LABELS[label]
            fields.setdefault(current, [])
            if match.group(2).strip():
                fields[current].append(match.group(2).strip())
            continue
        if current:
            fields.setdefault(current, []).append(raw_line)

    return fields


def field_text(fields: dict[str, list[str]], name: str) -> str:
    return clean_text(" ".join(line.strip() for line in fields.get(name, []) if line.strip()))


def field_paragraphs(fields: dict[str, list[str]], name: str) -> list[str]:
    return clean_paragraphs("\n".join(fields.get(name, [])))


def field_list(fields: dict[str, list[str]], name: str) -> list[str]:
    values: list[str] = []
    for paragraph in clean_paragraphs("\n".join(fields.get(name, []))):
        values.append(paragraph.removeprefix("• ").strip())
    return values


def split_tags(value: str) -> list[str]:
    tags = [clean_text(item) for item in re.split(r"[,;]", value) if clean_text(item)]
    return dedupe_strings(tags)


def fallback_articles(
    lead_paragraphs: list[str],
    topic: str,
    package_key: str,
    fallback_sources: list[dict[str, str]],
) -> list[dict[str, Any]]:
    body = "\n\n".join(lead_paragraphs)
    section_name = "Polska" if topic == "polska-swiat" else "AI"
    title = "Najważniejsze z wydania"
    return [
        {
            "id": stable_id(topic, package_key, 0, title),
            "section": section_name,
            "title": title,
            "standfirst": first_sentences(body, max_count=2),
            "whatHappened": build_what_happened(body),
            "whyItMatters": build_why_it_matters(section_name, topic, body),
            "deeperAnalysis": build_deeper_analysis(body, section_name, topic, fallback_sources[:1]),
            "contextPoints": build_context_points(body, section_name, topic),
            "sources": fallback_sources[:1],
            "priority": "Medium",
            "tags": tags_for(topic, section_name, body),
        }
    ]


def bullet_blocks(markdown: str) -> list[str]:
    blocks: list[str] = []
    current: list[str] = []
    for raw_line in markdown.splitlines():
        line = raw_line.strip()
        if not line:
            continue
        if line.startswith("|") or line.startswith("---"):
            continue
        if line.startswith("- ") or line.startswith("* "):
            if current:
                blocks.append(" ".join(current))
            current = [line[2:].strip()]
        elif current:
            current.append(line)
    if current:
        blocks.append(" ".join(current))
    return blocks


def heading_blocks(markdown: str) -> list[str]:
    blocks: list[str] = []
    current: list[str] = []
    for raw_line in markdown.splitlines():
        line = raw_line.strip()
        if line.startswith("### "):
            if current:
                blocks.append(" ".join(current))
            current = [line[4:].strip()]
        elif current and line:
            current.append(line)
    if current:
        blocks.append(" ".join(current))
    return blocks


def parse_podcast_topics(markdown: str) -> list[dict[str, str]]:
    topics: list[dict[str, str]] = []
    for raw_line in markdown.splitlines():
        line = raw_line.strip()
        if not line.startswith("|") or "---" in line:
            continue
        values = [clean_text(item) for item in line.split("|") if clean_text(item)]
        if len(values) < 3 or values[0].casefold() in {"priorytet", "priority"}:
            continue
        topics.append(
            {
                "priority": values[0],
                "title": values[1],
                "rationale": values[2],
                "sourcesLabel": values[3] if len(values) > 3 else "",
            }
        )
    return topics


def build_summary_bullets(lead_paragraphs: list[str], articles: list[dict[str, Any]], topic: str) -> list[str]:
    bullets = [f"{article['section']}: {article['title']}" for article in articles[:3]]
    if bullets:
        return bullets
    if lead_paragraphs:
        return [first_sentences(lead_paragraphs[0], max_count=1)]
    fallback = "Najważniejsze sygnały technologiczne są gotowe do przeglądu." if topic == "tech-news" else "Najważniejsze wydarzenia dnia są gotowe do przeglądu."
    return [fallback]


def build_what_happened(body: str) -> str:
    summary = first_sentences(body, max_count=2)
    return summary or "Raport odnotował materialny sygnał wymagający obserwacji."


def build_why_it_matters(section_name: str, topic: str, body: str) -> str:
    importance = {
        "AI": "wpływa na tempo adopcji modeli, agentów i narzędzi AI w produktach.",
        "Infrastruktura": "przekłada się na koszt, dostępność i skalowanie usług AI.",
        "Produkty": "pokazuje, które funkcje technologiczne przechodzą z eksperymentu do codziennego użycia.",
        "Regulacje": "może zmieniać ryzyko prawne i warunki wdrażania nowych technologii.",
        "Cyber": "dotyczy odporności systemów, ochrony danych i ryzyka operacyjnego.",
        "Polska": "może wpływać na decyzje administracji, firm i obywateli.",
        "Polityka": "wpływa na agendę publiczną i najbliższe decyzje polityczne.",
        "Świat": "zmienia kontekst międzynarodowy istotny dla Polski i Europy.",
        "Bezpieczeństwo": "dotyczy ryzyka strategicznego oraz odporności państwa.",
        "Gospodarka": "może przełożyć się na koszty, inwestycje i decyzje firm.",
        "Pogoda": "ma praktyczne znaczenie dla planowania dnia i bezpieczeństwa.",
    }.get(section_name, "warto obserwować dalszy rozwój tego wątku.")
    anchor = first_sentences(body, max_count=1)
    if anchor:
        return f"Ten sygnał jest ważny, bo {importance} Kluczowy fakt z raportu: {anchor}"
    return f"Ten sygnał jest ważny, bo {importance}"


def build_deeper_analysis(body: str, section_name: str, topic: str, sources: list[dict[str, str]]) -> list[str]:
    paragraphs = clean_paragraphs(body)
    analysis: list[str] = []
    repeated = {
        normalize_text(first_sentences(body, max_count=1)),
        normalize_text(first_sentences(body, max_count=2)),
        normalize_text(build_what_happened(body)),
    }
    for paragraph in paragraphs:
        if normalize_text(paragraph) not in repeated:
            analysis.append(paragraph)
        if len(analysis) >= 2:
            break
    analysis.append(build_why_it_matters(section_name, topic, body))
    if sources:
        source_label = ", ".join(source["title"] for source in sources[:2])
        analysis.append(f"Analiza opiera się na źródłach: {source_label}.")
    analysis.append(next_watch_sentence(section_name, topic))
    return dedupe_strings(analysis)[:5]


def build_context_points(body: str, section_name: str, topic: str) -> list[str]:
    first = first_sentences(body, max_count=1)
    return dedupe_strings(
        [
            f"Co się stało: {first}" if first else "Co się stało: raport wskazuje nowy sygnał do obserwacji.",
            f"Dlaczego ważne: {build_why_itMatters_short(section_name, topic)}",
            f"Na co patrzeć dalej: {next_watch_sentence(section_name, topic)}",
        ]
    )


def build_why_itMatters_short(section_name: str, topic: str) -> str:
    if topic == "tech-news":
        return {
            "AI": "zmiana może przyspieszać praktyczne wdrożenia AI.",
            "Infrastruktura": "infrastruktura decyduje o kosztach i dostępności produktów AI.",
            "Produkty": "produkty pokazują, co użytkownicy realnie zaczną stosować.",
            "Regulacje": "regulacje ustawiają ramy ryzyka i compliance.",
            "Cyber": "cyberbezpieczeństwo wpływa bezpośrednio na zaufanie i operacje.",
        }.get(section_name, "sygnał może zmienić priorytety technologiczne.")
    return {
        "Polska": "temat może wpływać na codzienne decyzje w kraju.",
        "Polityka": "decyzje polityczne ustawiają agendę publiczną.",
        "Świat": "kontekst międzynarodowy wpływa na Polskę i UE.",
        "Bezpieczeństwo": "bezpieczeństwo zmienia ocenę ryzyka.",
        "Gospodarka": "gospodarka wpływa na koszty i decyzje firm.",
        "Pogoda": "pogoda ma bezpośredni wpływ na planowanie i bezpieczeństwo.",
    }.get(section_name, "temat wymaga obserwacji w kolejnych dniach.")


def next_watch_sentence(section_name: str, topic: str) -> str:
    if topic == "tech-news":
        return f"W kolejnej rundzie warto sprawdzić, czy wątek {section_name.lower()} przełoży się na konkretne decyzje produktowe, regulacyjne albo infrastrukturalne."
    return f"W kolejnej rundzie warto sprawdzić, czy wątek {section_name.lower()} zyska decyzje instytucji, reakcje rynku albo nowe komunikaty źródłowe."


def article_title(body: str, section_name: str, topic: str, sources: list[dict[str, str]]) -> str:
    body = clean_text(body)
    if ":" in body[:120]:
        prefix = body.split(":", 1)[0].strip()
        if 4 <= len(prefix.split()) <= 14:
            return prefix
    entity_label = entity_title_label(body, sources, topic)
    if entity_label:
        if topic == "tech-news":
            suffix = {
                "AI": "nowy sygnał AI",
                "Infrastruktura": "infrastruktura AI i compute",
                "Produkty": "produktowy sygnał AI",
                "Regulacje": "regulacyjny sygnał technologiczny",
                "Cyber": "cyberbezpieczeństwo i ryzyko technologiczne",
            }.get(section_name, "ważny sygnał technologiczny")
        else:
            suffix = {
                "Polska": "krajowy sygnał dnia",
                "Polityka": "polityczny sygnał dnia",
                "Świat": "międzynarodowy kontekst dnia",
                "Bezpieczeństwo": "bezpieczeństwo i decyzje strategiczne",
                "Gospodarka": "gospodarka i koszty decyzji",
                "Pogoda": "pogoda i praktyczne ryzyko dnia",
            }.get(section_name, "ważny sygnał dnia")
        return f"{entity_label}: {suffix}"
    return compact_words(first_sentences(body, max_count=1), max_words=12) or "Najważniejszy wątek"


def entity_title_label(body: str, sources: list[dict[str, str]], topic: str) -> str:
    candidates = [source["title"] for source in sources[:2] if source.get("title")]
    catalog = (
        ["OpenAI", "Cloudflare", "NVIDIA", "Broadcom", "Qualcomm", "Google", "Microsoft", "Apple", "Anthropic", "Meta"]
        if topic == "tech-news"
        else ["Polska", "NATO", "MON", "KPRM", "UE", "Ukraina", "USA", "IMGW", "RCB", "Reuters"]
    )
    for item in catalog:
        if body.lower().find(item.lower()) != -1 and item not in candidates:
            candidates.append(item)
    cleaned = []
    for candidate in candidates:
        title = clean_text(candidate)
        if title and title.lower() not in {value.lower() for value in cleaned}:
            cleaned.append(title)
    return " i ".join(cleaned[:2])


def classify_section(text: str, topic: str) -> str:
    normalized = normalize_text(text)
    sections = TECH_SECTIONS if topic == "tech-news" else POLSKA_SECTIONS
    for section_name, needles in sections.items():
        if any(needle in normalized for needle in needles):
            return section_name
    return "Inne"


def tags_for(topic: str, section_name: str, body: str) -> list[str]:
    catalog = TECH_TAGS if topic == "tech-news" else POLSKA_TAGS
    normalized = normalize_text(body)
    tags = [section_name]
    for tag in catalog:
        if normalize_text(tag) in normalized and tag not in tags:
            tags.append(tag)
    return tags[:6]


def priority_from_text(text: str, index: int) -> str:
    lowered = normalize_text(text)
    if "high" in lowered or "wysok" in lowered:
        return "High"
    if "low" in lowered or "niski" in lowered:
        return "Low"
    if index < 3:
        return "High"
    return "Medium"


def extract_sources(markdown: str) -> list[dict[str, str]]:
    sources: list[dict[str, str]] = []
    seen: set[str] = set()
    for title, url in LINK_RE.findall(markdown):
        title = clean_text(title)
        if not title or url in seen:
            continue
        seen.add(url)
        sources.append({"title": title, "url": url})
    return sources


def clean_paragraphs(text: str) -> list[str]:
    paragraphs: list[str] = []
    current: list[str] = []

    def flush() -> None:
        nonlocal current
        value = clean_text(" ".join(current))
        current = []
        if value:
            paragraphs.append(value)

    for raw_line in text.replace("\r\n", "\n").splitlines():
        line = raw_line.strip()
        if not line:
            flush()
            continue
        if line.startswith("|") or line.startswith("---"):
            continue
        if line.startswith("- ") or line.startswith("* "):
            flush()
            paragraphs.append("• " + clean_text(line[2:]))
        else:
            current.append(line)
    flush()
    return paragraphs


def clean_text(value: str) -> str:
    value = re.sub(r"\[([^\]]+)\]\((https?://[^)]+)\)", r"\1", value)
    value = re.sub(r"[*_`#>]", "", value)
    value = re.sub(r"\s+", " ", value)
    return value.strip()


def first_sentences(value: str, max_count: int) -> str:
    value = clean_text(value)
    sentences = re.findall(r"[^.!?]+[.!?]?", value)
    result = " ".join(sentence.strip() for sentence in sentences[:max_count] if sentence.strip())
    return result.strip() or value


def compact_words(value: str, max_words: int) -> str:
    return " ".join(clean_text(value).split()[:max_words]).strip()


def parse_status(markdown: str) -> str:
    match = STATUS_RE.search(markdown)
    return clean_text(match.group("status")) if match else "Research update"


def parse_run_date_time(markdown: str, markdown_path: Path) -> tuple[str, str | None]:
    for candidate in [metadata_value("Date", markdown), markdown_path.stem]:
        if not candidate:
            continue
        match = DATE_RE.search(candidate)
        if not match:
            continue
        raw_time = match.group("time")
        time = None
        if raw_time:
            digits = raw_time.replace(":", "")
            if len(digits) == 4:
                time = f"{digits[:2]}:{digits[2:]}"
        return match.group("date"), time
    raise ValueError("missing report date")


def metadata_value(name: str, markdown: str) -> str | None:
    pattern = rf"^{re.escape(name)}:\s*(.+)$"
    match = re.search(pattern, markdown, flags=re.MULTILINE | re.IGNORECASE)
    return match.group(1).strip() if match else None


def infer_topic(path: Path) -> str:
    parts = path.parts
    for index, part in enumerate(parts):
        if part == "research" and index + 1 < len(parts):
            return parts[index + 1]
    return path.parents[1].name


def default_output_path(markdown_path: Path) -> Path:
    return markdown_path.parents[1] / "data" / f"{markdown_path.stem}-research.json"


def stable_id(topic: str, package_key: str, index: int, title: str) -> str:
    digest = hashlib.sha1(f"{topic}|{package_key}|{index}|{title}".encode("utf-8")).hexdigest()[:10]
    slug = re.sub(r"[^a-z0-9]+", "-", normalize_text(title)).strip("-")
    return f"{topic}-{package_key}-{index}-{slug or digest}-{digest}"


def normalize_heading(value: str) -> str:
    return normalize_text(clean_text(value))


def normalize_text(value: str) -> str:
    replacements = str.maketrans("ąćęłńóśźżĄĆĘŁŃÓŚŹŻ", "acelnoszzACELNOSZZ")
    return re.sub(r"\s+", " ", value.translate(replacements).casefold()).strip()


def dedupe_strings(values: list[str]) -> list[str]:
    result: list[str] = []
    seen: set[str] = set()
    for value in values:
        clean = clean_text(value)
        key = normalize_text(clean)
        if clean and key not in seen:
            seen.add(key)
            result.append(clean)
    return result


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("markdown_report", type=Path)
    parser.add_argument("json_output", nargs="?", type=Path)
    parser.add_argument("--topic", choices=sorted(SUPPORTED_TOPICS), help="Override topic slug")
    parser.add_argument(
        "--require-app-articles",
        action="store_true",
        help="Fail unless ## Artykuły do aplikacji contains complete app-ready article subsections",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    output = args.json_output or default_output_path(args.markdown_report)
    render_research_data(
        args.markdown_report,
        output,
        topic=args.topic,
        require_app_articles=args.require_app_articles,
    )
    print(f"research data written: {output}")


if __name__ == "__main__":
    main()
