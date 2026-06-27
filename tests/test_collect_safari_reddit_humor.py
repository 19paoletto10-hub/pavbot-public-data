from __future__ import annotations

import importlib.util
from datetime import datetime
from pathlib import Path


def load_collector():
    module_path = Path(__file__).resolve().parents[1] / "scripts" / "collect_safari_reddit_humor.py"
    spec = importlib.util.spec_from_file_location("collect_safari_reddit_humor", module_path)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


def test_curate_posts_keeps_safe_reddit_items_and_sorts_by_score():
    collector = load_collector()
    posts = [
        {
            "title": "Kiedy deploy jednak przechodzi",
            "url": "https://www.reddit.com/r/ProgrammerHumor/comments/deploy/test/",
            "sourceName": "r/ProgrammerHumor",
            "imageURL": "https://i.redd.it/deploy.png",
            "score": 120,
            "comments": 8,
        },
        {
            "title": "NSFW item",
            "url": "https://www.reddit.com/r/memes/comments/bad/test/",
            "sourceName": "r/memes",
            "score": 9999,
            "comments": 1,
        },
        {
            "title": "Największy temat dnia na Reddicie",
            "url": "/r/Polska_wpz/comments/topic/test/",
            "sourceName": "r/Polska_wpz",
            "score": 450,
            "comments": 67,
        },
    ]

    items = collector.curate_posts(posts, max_items=6)

    assert [item["title"] for item in items] == [
        "Największy temat dnia na Reddicie",
        "Kiedy deploy jednak przechodzi",
    ]
    assert items[0]["sourceURL"] == "https://www.reddit.com/r/Polska_wpz/comments/topic/test/"
    assert items[0]["caption"]
    assert items[0]["tags"]


def test_curate_posts_adds_reddit_radar_detail_metadata():
    collector = load_collector()
    posts = [
        {
            "title": "Kiedy AI robi code review po piątku",
            "url": "https://www.reddit.com/r/ProgrammerHumor/comments/ai_review/test/",
            "sourceName": "r/ProgrammerHumor",
            "postText": "Autor żartuje, że AI znalazło błąd, którego nikt nie napisał.",
            "score": 1200,
            "comments": 91,
            "commentSnippets": [
                {
                    "body": "Najbardziej realistyczne jest to, że wszyscy udają, że rozumieją komentarz bota.",
                    "score": 44,
                },
                {
                    "body": "To code review wygląda jak stand-up z diffem w tle.",
                    "score": 31,
                },
                {
                    "body": "Senior dev właśnie zaakceptował, bo zielone testy brzmią wystarczająco naukowo.",
                    "score": 18,
                },
                {
                    "body": "Czwarty komentarz nie powinien wejść do skrótu.",
                    "score": 99,
                },
            ],
        }
    ]

    items = collector.curate_posts(posts, max_items=6)

    assert items[0]["categoryLabel"] == "AI, dev"
    assert items[0]["postText"] == "Autor żartuje, że AI znalazło błąd, którego nikt nie napisał."
    assert "AI" in items[0]["whyFunny"]
    assert len(items[0]["commentHighlights"]) == 3
    assert items[0]["commentHighlights"][0] == {
        "id": "comment-1",
        "summary": "Najbardziej realistyczne jest to, że wszyscy udają, że rozumieją komentarz bota.",
        "explanation": "Komentarz jest zabawny, bo dopowiada codzienny absurd z wątku i zamienia go w puentę.",
        "score": 44,
    }


def test_build_digest_uses_codex_safari_contract_and_next_even_hour_slot():
    collector = load_collector()
    now = datetime.fromisoformat("2026-06-27T06:06:30+00:00")
    items = [
        {
            "id": "topic",
            "title": "Największy temat dnia na Reddicie",
            "caption": "Krótki sygnał społecznościowy, nie źródło faktów.",
            "sourceName": "r/Polska_wpz",
            "sourceURL": "https://www.reddit.com/r/Polska_wpz/comments/topic/test/",
            "imageURL": None,
            "score": 450,
            "comments": 67,
            "tags": ["PL", "trend"],
            "categoryLabel": "PL",
        }
    ]

    digest = collector.build_digest(items=items, generated_at=now, interval_hours=2, timezone_name="Europe/Warsaw")

    assert digest["source"] == "Codex Safari Reddit radar"
    assert digest["title"] == "<RR> Reddit Radar"
    assert digest["summary"] == (
        "Kategorie: PL. Najmocniej wybija się: "
        "<u>Największy temat dnia na Reddicie</u>."
    )
    assert digest["refreshIntervalHours"] == 2
    assert digest["displayTime"] == "08:06"
    assert digest["nextRefreshAt"] == "2026-06-27T10:06:00+02:00"
    assert digest["items"] == items


def test_load_env_file_sets_missing_values_without_overriding(monkeypatch, tmp_path):
    collector = load_collector()
    env_file = tmp_path / ".env"
    env_file.write_text(
        "PAVBOT_HUMOR_INGEST_TOKEN=file-token\n"
        "PAVBOT_HUMOR_NOTIFIER_URL=https://notify.example.com\n",
        encoding="utf-8",
    )
    monkeypatch.setenv("PAVBOT_HUMOR_INGEST_TOKEN", "existing-token")
    monkeypatch.delenv("PAVBOT_HUMOR_NOTIFIER_URL", raising=False)

    collector.load_env_file(env_file)

    assert collector.os.environ["PAVBOT_HUMOR_INGEST_TOKEN"] == "existing-token"
    assert collector.os.environ["PAVBOT_HUMOR_NOTIFIER_URL"] == "https://notify.example.com"
