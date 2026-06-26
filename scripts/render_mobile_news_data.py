#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import re
from pathlib import Path
from typing import Any


TOPIC = "aktualne-wydarzenia-mobile"
DEFAULT_SECTION_ORDER = ["Ogólne", "Polska", "Polityka", "Sprawy zagraniczne", "Technologia"]
DATE_RE = re.compile(r"(?P<date>\d{4}-\d{2}-\d{2})(?:[ T-](?P<time>\d{2}:?\d{2}))?")
LINK_RE = re.compile(r"\[([^\]]+)\]\((https?://[^)]+)\)")


def build_mobile_news_payload(markdown: str, source_path: Path) -> dict[str, Any]:
    sections = markdown_sections(markdown)
    run_date, run_time = metadata_date(markdown, source_path)
    status = metadata_value("Status", markdown) or "Material update"
    lead_paragraphs = clean_paragraphs(section_body(sections, ["Summary", "Podsumowanie"]))
    if not lead_paragraphs:
        lead_paragraphs = ["Wydanie zawiera uporządkowane najważniejsze informacje dnia do czytania w aplikacji Pavbot."]

    magazine_sections = parse_gazeta(section_body(sections, ["Gazeta"]))
    if not magazine_sections:
        magazine_sections = fallback_sections_from_new_facts(
            section_body(sections, ["Nowe fakty", "New facts", "Key facts"]),
            interpretation=section_body(sections, ["Interpretacja", "Analysis"]),
        )

    checked_sources = unique_sources(
        extract_sources(section_body(sections, ["Sources", "Źródła", "Source"]))
        + [source for section in magazine_sections for article in section["articles"] for source in article["sources"]]
    )

    return {
        "schemaVersion": 1,
        "topic": TOPIC,
        "runDate": run_date,
        "runTime": run_time,
        "status": status,
        "headline": headline_from_lead(lead_paragraphs, magazine_sections),
        "leadParagraphs": lead_paragraphs,
        "sections": magazine_sections,
        "checkedSources": checked_sources,
        "audioArtifacts": [],
    }


def parse_gazeta(body: str) -> list[dict[str, Any]]:
    if not body.strip():
        return []

    raw_sections = split_headings(body, level=3)
    sections: list[dict[str, Any]] = []
    for title, section_body_text in raw_sections:
        articles = parse_gazeta_articles(title, section_body_text)
        if not articles:
            continue
        sections.append(
            {
                "id": slugify(title),
                "title": title,
                "summary": section_summary(title, articles),
                "articles": articles,
            }
        )
    return sort_sections(sections)


def parse_gazeta_articles(section_title: str, body: str) -> list[dict[str, Any]]:
    raw_articles = split_headings(body, level=4)
    if not raw_articles and body.strip():
        raw_articles = [(section_title, body)]

    articles: list[dict[str, Any]] = []
    for index, (title, article_body) in enumerate(raw_articles):
        lead = field_text(article_body, "Lead") or first_sentence(clean_markdown(article_body))
        facts = field_list(article_body, "Fakty") or bullet_lines(article_body) or [lead]
        analysis = field_text(article_body, "Analiza") or "Ten wątek wymaga obserwacji w kolejnych komunikatach źródłowych."
        why = (
            field_text(article_body, "Dlaczego ważne")
            or field_text(article_body, "Dlaczego to ważne")
            or why_it_matters(section_title)
        )
        sources = extract_sources(article_body)
        article = make_article(
            section_title=section_title,
            title=title,
            lead=lead,
            facts=facts,
            analysis=analysis,
            why_it_matters=why,
            sources=sources,
            index=index,
        )
        articles.append(article)
    return articles


def fallback_sections_from_new_facts(body: str, interpretation: str) -> list[dict[str, Any]]:
    blocks = bullet_blocks(body)
    if not blocks:
        return [
            {
                "id": "ogolne",
                "title": "Ogólne",
                "summary": "Brak materialnej zmiany w najważniejszych sprawdzonych źródłach.",
                "articles": [
                    make_article(
                        section_title="Ogólne",
                        title="Brak materialnej zmiany",
                        lead="Nie znaleziono nowego faktu o wysokiej wadze publicznej.",
                        facts=["Sprawdzono najważniejsze źródła dla dzisiejszego przebiegu."],
                        analysis="Brak nowego faktu ogranicza szum i pomaga traktować poprzednie ustalenia jako nadal aktualne.",
                        why_it_matters="Aplikacja może jasno pokazać, że automatyzacja wykonała pracę, nawet jeśli nie znalazła przełomu.",
                        sources=[],
                        index=0,
                    )
                ],
            }
        ]

    interpretation_text = first_sentence(clean_markdown(interpretation))
    grouped: dict[str, list[dict[str, Any]]] = {}
    for index, block in enumerate(blocks):
        clean = clean_markdown(block)
        section = classify_section(clean)
        sources = extract_sources(block)
        grouped.setdefault(section, []).append(
            make_article(
                section_title=section,
                title=title_from_text(clean, section),
                lead=first_sentence(clean),
                facts=[clean],
                analysis=interpretation_text or "Ten fakt jest częścią szerszego obrazu dnia i wymaga dalszego monitoringu.",
                why_it_matters=why_it_matters(section),
                sources=sources,
                index=index,
            )
        )

    return sort_sections(
        [
            {
                "id": slugify(section),
                "title": section,
                "summary": section_summary(section, articles),
                "articles": articles,
            }
            for section, articles in grouped.items()
        ]
    )


def make_article(
    section_title: str,
    title: str,
    lead: str,
    facts: list[str],
    analysis: str,
    why_it_matters: str,
    sources: list[dict[str, str]],
    index: int,
) -> dict[str, Any]:
    clean_title = clean_markdown(title) or "Najważniejszy wątek"
    clean_lead = clean_markdown(lead) or clean_title
    clean_facts = [clean_markdown(fact) for fact in facts if clean_markdown(fact)]
    clean_analysis = clean_markdown(analysis)
    clean_why = clean_markdown(why_it_matters)
    tags = tags_for(section_title, " ".join([clean_title, clean_lead, clean_analysis]))
    return {
        "id": f"{slugify(section_title)}-{index + 1}-{slugify(clean_title)[:48] or 'article'}",
        "section": section_title,
        "title": clean_title,
        "lead": clean_lead,
        "facts": clean_facts or [clean_lead],
        "analysis": clean_analysis or "Ten wątek wymaga obserwacji w kolejnych komunikatach źródłowych.",
        "whyItMatters": clean_why or why_it_matters(section_title),
        "sources": unique_sources(sources),
        "tags": tags,
        "ttsText": tts_text(clean_title, clean_lead, clean_facts, clean_analysis, clean_why),
        "priority": priority_for(clean_title, clean_lead, clean_analysis),
    }


def metadata_date(markdown: str, source_path: Path) -> tuple[str, str | None]:
    raw = metadata_value("Date", markdown) or source_path.stem
    match = DATE_RE.search(raw)
    if not match:
        match = DATE_RE.search(source_path.stem)
    if not match:
        return source_path.stem[:10], None
    run_time = match.group("time")
    if run_time:
        run_time = run_time.replace(":", "")
        run_time = f"{run_time[:2]}:{run_time[2:]}"
    return match.group("date"), run_time


def metadata_value(name: str, markdown: str) -> str | None:
    pattern = re.compile(rf"(?im)^\s*#?\s*{re.escape(name)}\s*:\s*(.+)$")
    match = pattern.search(markdown)
    return match.group(1).strip() if match else None


def markdown_sections(markdown: str) -> dict[str, str]:
    return {title: body for title, body in split_headings(markdown, level=2)}


def section_body(sections: dict[str, str], names: list[str]) -> str:
    for title, body in sections.items():
        if any(name.casefold() in title.casefold() for name in names):
            return body
    return ""


def split_headings(markdown: str, level: int) -> list[tuple[str, str]]:
    marker = "#" * level + " "
    result: list[tuple[str, str]] = []
    current_title = ""
    current_lines: list[str] = []
    for line in markdown.replace("\r\n", "\n").splitlines():
        if line.startswith(marker) and not line.startswith(marker + "#"):
            if current_title:
                result.append((current_title, "\n".join(current_lines)))
            current_title = line[len(marker) :].strip()
            current_lines = []
        elif current_title:
            current_lines.append(line)
    if current_title:
        result.append((current_title, "\n".join(current_lines)))
    return result


def field_text(text: str, field: str) -> str:
    pattern = re.compile(rf"(?ims)^\s*{re.escape(field)}\s*:\s*(.+?)(?=^\s*(?:Lead|Fakty|Analiza|Dlaczego ważne|Dlaczego to ważne)\s*:|\Z)")
    match = pattern.search(text)
    return clean_markdown(match.group(1)) if match else ""


def field_list(text: str, field: str) -> list[str]:
    raw = field_text(text, field)
    return bullet_lines(raw)


def bullet_lines(text: str) -> list[str]:
    values: list[str] = []
    for line in text.splitlines():
        stripped = line.strip()
        if stripped.startswith("- ") or stripped.startswith("* "):
            values.append(clean_markdown(stripped[2:]))
    return values


def bullet_blocks(text: str) -> list[str]:
    blocks: list[str] = []
    current: list[str] = []
    for raw_line in text.splitlines():
        line = raw_line.strip()
        if not line:
            continue
        if line.startswith("- ") or line.startswith("* "):
            if current:
                blocks.append(" ".join(current))
            current = [line[2:]]
        elif current and not line.startswith("|") and not line.startswith("---"):
            current.append(line)
    if current:
        blocks.append(" ".join(current))
    return blocks


def extract_sources(text: str) -> list[dict[str, str]]:
    return unique_sources(
        [
            {"title": match.group(1).strip(), "url": match.group(2).strip()}
            for match in LINK_RE.finditer(text)
        ]
    )


def unique_sources(sources: list[dict[str, str]]) -> list[dict[str, str]]:
    seen: set[str] = set()
    result: list[dict[str, str]] = []
    for source in sources:
        title = str(source.get("title") or "").strip()
        url = str(source.get("url") or "").strip()
        if not title or not url or url in seen:
            continue
        seen.add(url)
        result.append({"title": title, "url": url})
    return result


def clean_paragraphs(text: str) -> list[str]:
    paragraphs: list[str] = []
    current: list[str] = []
    for raw_line in text.replace("\r\n", "\n").splitlines():
        line = raw_line.strip()
        if not line:
            flush_paragraph(current, paragraphs)
            current = []
            continue
        if line.startswith("|") or line.startswith("---"):
            continue
        current.append(line)
    flush_paragraph(current, paragraphs)
    return paragraphs


def flush_paragraph(lines: list[str], paragraphs: list[str]) -> None:
    value = clean_markdown(" ".join(lines))
    if value:
        paragraphs.append(value)


def clean_markdown(text: str) -> str:
    value = LINK_RE.sub(r"\1", text)
    value = re.sub(r"[*_`#>]", "", value)
    value = re.sub(r"(?m)^\s*[-*]\s*", "", value)
    value = re.sub(r"\s+", " ", value)
    return value.strip()


def first_sentence(text: str) -> str:
    clean = clean_markdown(text)
    parts = re.split(r"(?<=[.!?])\s+", clean)
    return (parts[0] if parts else clean).strip()


def title_from_text(text: str, section: str) -> str:
    sentence = first_sentence(text)
    words = sentence.split()
    if len(words) <= 10:
        return sentence
    return f"{section}: {' '.join(words[:9])}"


def headline_from_lead(lead_paragraphs: list[str], sections: list[dict[str, Any]]) -> str:
    if sections:
        return f"Wydanie dnia: {sections[0]['title']} i najważniejsze sygnały"
    return compact_words(lead_paragraphs[0], 9) if lead_paragraphs else "Wydanie dnia"


def section_summary(section_title: str, articles: list[dict[str, Any]]) -> str:
    if len(articles) == 1:
        return articles[0]["lead"]
    return f"{section_title}: {len(articles)} uporządkowane wątki do szybkiego przeglądu."


def classify_section(text: str) -> str:
    value = text.casefold()
    if any(word in value for word in ["rcb", "imgw", "upał", "pogod", "pożar", "powódź"]):
        return "Ogólne"
    if any(word in value for word in ["sejm", "senat", "rząd", "prezydent", "wybor", "polity"]):
        return "Polityka"
    if any(word in value for word in ["nato", "ue", "ukrain", "iran", "usa", "rosj", "świat", "consilium"]):
        return "Sprawy zagraniczne"
    if any(word in value for word in ["ai", "technolog", "cyber", "aplikac", "system"]):
        return "Technologia"
    if any(word in value for word in ["polsk", "kprm", "mon", "msz", "gdańsk", "radom"]):
        return "Polska"
    return "Ogólne"


def why_it_matters(section_title: str) -> str:
    mapping = {
        "Ogólne": "To pomaga szybko ocenić, czy wydarzenie wpływa na codzienne decyzje i bezpieczeństwo.",
        "Polska": "To pokazuje, jak decyzje krajowe mogą przełożyć się na obywateli, instytucje i lokalne działania.",
        "Polityka": "To wskazuje, które decyzje i spory mogą zmienić kierunek działań publicznych.",
        "Sprawy zagraniczne": "To ustawia polskie wydarzenia w szerszym kontekście bezpieczeństwa i dyplomacji.",
        "Technologia": "To pomaga odróżnić realną zmianę technologiczną od szumu informacyjnego.",
    }
    return mapping.get(section_title, mapping["Ogólne"])


def tags_for(section_title: str, text: str) -> list[str]:
    candidates = [
        section_title,
        "Polska",
        "Ukraina",
        "NATO",
        "UE",
        "Bezpieczeństwo",
        "Gospodarka",
        "Pogoda",
        "Technologia",
        "RCB",
        "IMGW",
        "KPRM",
    ]
    found = [candidate for candidate in candidates if candidate == section_title or candidate.casefold() in text.casefold()]
    return list(dict.fromkeys(found))[:5] or [section_title]


def priority_for(*parts: str) -> str:
    text = " ".join(parts).casefold()
    if any(word in text for word in ["alarm", "bezpieczeń", "nato", "wojna", "rcb", "krytycz"]):
        return "High"
    if any(word in text for word in ["brak materialnej zmiany", "bez nowego faktu"]):
        return "Low"
    return "Medium"


def tts_text(title: str, lead: str, facts: list[str], analysis: str, why: str) -> str:
    text = ". ".join([title, lead] + facts[:3] + [analysis, why])
    text = re.sub(r"https?://\S+", "", text)
    text = re.sub(r"\s+", " ", text)
    return text.strip(" .") + "."


def sort_sections(sections: list[dict[str, Any]]) -> list[dict[str, Any]]:
    order = {title: index for index, title in enumerate(DEFAULT_SECTION_ORDER)}
    return sorted(sections, key=lambda section: order.get(section["title"], 999))


def slugify(value: str) -> str:
    polish = str.maketrans("ąćęłńóśżźĄĆĘŁŃÓŚŻŹ", "acelnoszzACELNOSZZ")
    slug = value.translate(polish).casefold()
    slug = re.sub(r"[^a-z0-9]+", "-", slug).strip("-")
    return slug or "section"


def compact_words(text: str, max_words: int) -> str:
    words = text.split()
    return " ".join(words[:max_words])


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Render Pavbot mobileNewsData JSON from a 10:15 Markdown report.")
    parser.add_argument("source", type=Path, help="Input report Markdown path")
    parser.add_argument("output", type=Path, help="Output mobileNewsData JSON path")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    payload = build_mobile_news_payload(args.source.read_text(encoding="utf-8"), args.source)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"mobile news data written: {args.output}")


if __name__ == "__main__":
    main()
