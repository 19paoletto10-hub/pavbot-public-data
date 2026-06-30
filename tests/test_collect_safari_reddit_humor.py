from __future__ import annotations

import importlib.util
import json
from datetime import datetime
from pathlib import Path
from types import SimpleNamespace

import pytest


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
                    "body": "Najtrafniejszy komentarz powinien wejść pierwszy mimo dalszej pozycji w wątku.",
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
        "summary": "Najtrafniejszy komentarz powinien wejść pierwszy mimo dalszej pozycji w wątku.",
        "originalBody": "Najtrafniejszy komentarz powinien wejść pierwszy mimo dalszej pozycji w wątku.",
        "explanation": "Komentarz jest ciekawy, bo rozwija żart o AI i pokazuje, jak ludzie dopisują puentę do technologicznego absurdu.",
        "score": 99,
    }


def test_comment_highlights_filter_deleted_toxic_and_limit_to_three():
    collector = load_collector()

    highlights = collector.comment_highlights_from(
        [
            {"body": "[deleted]", "score": 999},
            {"body": "kill yourself", "score": 998},
            {"body": "Komentarz o rytuale po zbyt łatwym deployu.", "score": 10},
            {"body": "Najcelniejsza puenta o tym, że sukces wygląda podejrzanie.", "score": 120},
            {"body": "Druga dobra obserwacja o czekaniu na awarię.", "score": 80},
            {"body": "Trzecia obserwacja o zielonym CI.", "score": 30},
            {"body": "Czwarta bezpieczna obserwacja nie powinna wejść.", "score": 20},
        ],
        title="Kiedy deploy przechodzi za pierwszym razem",
        category_label="dev",
    )

    assert [highlight["score"] for highlight in highlights] == [120, 80, 30]
    assert len(highlights) == 3
    assert all("kill yourself" not in highlight["summary"] for highlight in highlights)
    assert highlights[0]["originalBody"] == "Najcelniejsza puenta o tym, że sukces wygląda podejrzanie."


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


def test_merge_reddit_radar_items_adds_unique_and_replaces_six_oldest_when_full():
    collector = load_collector()
    previous = [
        {
            "id": f"old-{index}",
            "title": f"Stary temat {index}",
            "sourceURL": f"https://www.reddit.com/r/test/comments/old{index}/topic/",
            "score": index,
            "comments": index,
            "radarFirstSeenAt": f"2026-06-27T{index:02d}:00:00+00:00",
        }
        for index in range(12)
    ]
    fresh = [
        {
            "id": "duplicate",
            "title": "Stary temat 10",
            "sourceURL": "https://www.reddit.com/r/test/comments/old10/topic/",
            "score": 999,
            "comments": 999,
        },
        *[
            {
                "id": f"new-{index}",
                "title": f"Nowy intrygujący temat {index}",
                "sourceURL": f"https://www.reddit.com/r/test/comments/new{index}/topic/",
                "score": 100 + index,
                "comments": 50 + index,
            }
            for index in range(7)
        ],
    ]

    merged = collector.merge_reddit_radar_items(
        previous,
        fresh,
        max_items=12,
        replace_count=6,
        generated_at=datetime.fromisoformat("2026-06-28T00:06:00+00:00"),
    )

    urls = [item["sourceURL"] for item in merged]
    assert len(merged) == 12
    assert len(set(urls)) == 12
    assert all(f"/old{index}/" not in " ".join(urls) for index in range(6))
    assert all(f"/old{index}/" in " ".join(urls) for index in range(6, 12))
    assert sum("/new" in url for url in urls) == 6
    assert all(item.get("radarFirstSeenAt") for item in merged)


def test_load_recent_reddit_radar_history_keys_uses_last_five_days(tmp_path):
    collector = load_collector()
    data_dir = tmp_path / "research" / "reddit-radar" / "data"
    data_dir.mkdir(parents=True)
    recent_payload = {
        "items": [
            {
                "title": "Świeży temat",
                "sourceURL": "https://www.reddit.com/r/test/comments/recent/topic/",
            }
        ]
    }
    old_payload = {
        "items": [
            {
                "title": "Stary temat",
                "sourceURL": "https://www.reddit.com/r/test/comments/old/topic/",
            }
        ]
    }
    (data_dir / "2026-06-29-1010-reddit-radar.json").write_text(
        json.dumps(recent_payload, ensure_ascii=False),
        encoding="utf-8",
    )
    (data_dir / "2026-06-20-1010-reddit-radar.json").write_text(
        json.dumps(old_payload, ensure_ascii=False),
        encoding="utf-8",
    )

    seen = collector.load_recent_reddit_radar_history_keys(
        tmp_path / "research" / "reddit-radar",
        generated_at=datetime.fromisoformat("2026-06-30T02:08:00+00:00"),
        lookback_days=5,
    )

    assert "https://www.reddit.com/r/test/comments/recent/topic" in seen
    assert "https://www.reddit.com/r/test/comments/old/topic" not in seen


def test_default_subreddits_include_intriguing_sources():
    collector = load_collector()

    defaults = collector.parse_subreddits("")

    assert "AskReddit" in defaults
    assert "mildlyinfuriating" in defaults
    assert "OutOfTheLoop" in defaults
    assert len(defaults) >= 8


def test_write_reddit_radar_artifacts_writes_raw_final_and_markdown(tmp_path):
    collector = load_collector()
    digest = {
        "id": "humor-2026-06-27-0806",
        "title": "<RR> Reddit Radar",
        "summary": "Kategorie: dev. Najmocniej wybija się: <u>Kiedy deploy przechodzi</u>.",
        "generatedAt": "2026-06-27T06:06:00+00:00",
        "displayTime": "08:06",
        "nextRefreshAt": "2026-06-27T10:06:00+02:00",
        "refreshIntervalHours": 2,
        "source": "Codex Safari Reddit radar",
        "items": [
            {
                "id": "deploy",
                "title": "Kiedy deploy przechodzi",
                "caption": "Ten typ humoru zna każdy, kto choć raz czekał na zielone CI.",
                "sourceName": "r/ProgrammerHumor",
                "sourceURL": "https://www.reddit.com/r/ProgrammerHumor/comments/deploy/test/",
                "imageURL": "https://i.redd.it/deploy.png",
                "score": 1200,
                "comments": 42,
                "tags": ["dev"],
                "categoryLabel": "dev",
                "postText": "Autor żartuje, że deploy przeszedł za łatwo.",
                "whyFunny": "Zabawne, bo sukces wygląda podejrzanie.",
                "rawCommentSnippets": [
                    {"body": "Surowy komentarz zostaje tylko w raw JSON.", "score": 55}
                ],
                "commentHighlights": [
                    {
                        "id": "comment-1",
                        "summary": "Komentarz dotyczy czekania na awarię po zielonym CI.",
                        "originalBody": "Surowy komentarz zostaje tylko w raw JSON.",
                        "explanation": "Śmieszy, bo odwraca sukces w podejrzany sygnał.",
                        "score": 55,
                    }
                ],
                "commentAnalysisStatus": "reviewed",
                "commentAnalysisSource": "codex-computer-use-safari",
                "commentAnalysisNote": "Komentarz sprawdzony w widoku posta Safari.",
            }
        ],
    }

    paths = collector.write_reddit_radar_artifacts(digest, output_root=tmp_path / "research" / "reddit-radar")

    assert paths["raw"].name == "2026-06-27-0806-reddit-radar-raw.json"
    assert paths["final"].name == "2026-06-27-0806-reddit-radar.json"
    assert paths["markdown"].name == "2026-06-27-0806-reddit-radar.md"
    raw_payload = collector.json.loads(paths["raw"].read_text(encoding="utf-8"))
    final_payload = collector.json.loads(paths["final"].read_text(encoding="utf-8"))
    markdown = paths["markdown"].read_text(encoding="utf-8")
    assert raw_payload["items"][0]["rawCommentSnippets"][0]["body"] == "Surowy komentarz zostaje tylko w raw JSON."
    assert "rawCommentSnippets" not in final_payload["items"][0]
    assert final_payload["items"][0]["commentHighlights"][0]["originalBody"] == "Surowy komentarz zostaje tylko w raw JSON."
    assert raw_payload["items"][0]["commentAnalysisStatus"] == "reviewed"
    assert "commentAnalysisStatus" not in final_payload["items"][0]
    assert "## Analiza komentarzy" in markdown
    assert "Status analizy komentarzy: reviewed" in markdown
    assert "Czego dotyczy" in markdown
    assert "Dlaczego ciekawe/smieszne" in markdown


def test_main_publishes_audit_artifacts_after_collecting_safari_digest(monkeypatch, tmp_path):
    collector = load_collector()
    publish_calls = []

    monkeypatch.setattr(
        collector,
        "collect_posts_from_safari",
        lambda subreddits: [
            {
                "title": "Kiedy deploy przechodzi za pierwszym razem",
                "url": "https://www.reddit.com/r/ProgrammerHumor/comments/deploy/test/",
                "sourceName": "r/ProgrammerHumor",
                "score": 1200,
                "comments": 42,
                "commentSnippets": [{"body": "A teraz czekamy na alarm.", "score": 55}],
            }
        ],
    )
    monkeypatch.setattr(collector, "enrich_items_from_safari", lambda items: items)
    monkeypatch.setattr(
        collector,
        "publish_reddit_radar_artifacts",
        lambda *, artifact_root, expected_paths: publish_calls.append(
            {"artifact_root": artifact_root, "expected_paths": expected_paths}
        ),
        raising=False,
    )
    monkeypatch.setattr(
        collector.sys,
        "argv",
        [
            "collect_safari_reddit_humor.py",
            "--artifact-root",
            str(tmp_path / "research" / "reddit-radar"),
            "--max-items",
            "1",
        ],
    )

    assert collector.main() == 0

    assert len(publish_calls) == 1
    expected_paths = set(publish_calls[0]["expected_paths"].values())
    assert any(path.name.endswith("-reddit-radar.md") for path in expected_paths)
    assert any(path.name.endswith("-reddit-radar.json") for path in expected_paths)
    assert any(path.name.endswith("-reddit-radar-raw.json") for path in expected_paths)


def test_publish_reddit_radar_artifacts_accepts_repo_relative_expected_paths(monkeypatch):
    collector = load_collector()
    expected_paths = {
        "raw": Path("research/reddit-radar/data/2026-06-28-0408-reddit-radar-raw.json"),
        "final": Path("research/reddit-radar/data/2026-06-28-0408-reddit-radar.json"),
        "markdown": Path("research/reddit-radar/runs/2026-06-28-0408-reddit-radar.md"),
    }
    manifest = {"artifacts": [{"path": str(path)} for path in expected_paths.values()]}
    commands = []

    def fake_run(args, **kwargs):
        commands.append(args)
        if args[:2] == ["git", "show"]:
            return SimpleNamespace(stdout=json.dumps(manifest), returncode=0)
        return SimpleNamespace(stdout="", stderr="", returncode=0)

    monkeypatch.setattr(collector.subprocess, "run", fake_run)

    collector.publish_reddit_radar_artifacts(
        artifact_root=collector.DEFAULT_ARTIFACT_ROOT,
        expected_paths=expected_paths,
    )

    assert any(args[:2] == ["git", "cat-file"] for args in commands)


def reddit_radar_test_digest(item):
    return {
        "id": "humor-test",
        "title": "<RR> Reddit Radar",
        "summary": "Kategorie: dev. Najmocniej wybija się: <u>test</u>.",
        "generatedAt": "2026-06-27T06:06:00+00:00",
        "displayTime": "08:06",
        "nextRefreshAt": "2026-06-27T10:06:00+02:00",
        "refreshIntervalHours": 2,
        "source": "Codex Safari Reddit radar",
        "items": [item],
    }


def reviewed_reddit_radar_item():
    return {
        "id": "deploy",
        "title": "Kiedy deploy przechodzi za pierwszym razem",
        "caption": "Ten typ humoru zna każdy, kto choć raz czekał na zielone CI.",
        "sourceName": "r/ProgrammerHumor",
        "sourceURL": "https://www.reddit.com/r/ProgrammerHumor/comments/deploy/test/",
        "imageURL": None,
        "score": 1200,
        "comments": 42,
        "tags": ["dev"],
        "categoryLabel": "dev",
        "postText": "Autor pokazuje zespół, który boi się zbyt gładkiego wdrożenia.",
        "whyFunny": "Śmieszy, bo zamienia sukces techniczny w podejrzany sygnał, który zna każdy dyżurujący po deployu.",
        "commentHighlights": [
            {
                "id": "comment-1",
                "summary": "Komentarz dotyczy zespołu, który po zielonym CI i tak czeka na ukrytą awarię.",
                "originalBody": "Po zielonym CI i tak wszyscy siedzą cicho, bo czekają na ukrytą awarię.",
                "explanation": "Puenta działa, bo pokazuje nerwowy rytuał sprawdzania monitoringu po czymś, co powinno być dobrą wiadomością.",
                "score": 55,
            },
            {
                "id": "comment-2",
                "summary": "Drugi komentarz opisuje odświeżanie dashboardów zamiast świętowania sukcesu.",
                "originalBody": "Nie świętujemy, tylko odświeżamy dashboardy, aż coś zacznie migać.",
                "explanation": "Jest trafny, bo dopowiada realny gest z pracy: sukces nie uspokaja, tylko uruchamia kontrolę szkód.",
                "score": 40,
            },
            {
                "id": "comment-3",
                "summary": "Trzeci komentarz żartuje, że cisza po deployu brzmi bardziej podejrzanie niż alarm.",
                "originalBody": "Cisza po deployu jest gorsza od alarmu, bo wtedy nie wiadomo, gdzie patrzeć.",
                "explanation": "Jest zabawny, bo odwraca normalną logikę awarii: brak problemu staje się problemem samym w sobie.",
                "score": 30,
            },
        ],
    }


def write_post_file_pair(tmp_path, collector, *, final_item, raw_item=None):
    data_dir = tmp_path / "research" / "reddit-radar" / "data"
    data_dir.mkdir(parents=True)
    final_path = data_dir / "2026-06-27-0806-reddit-radar.json"
    raw_path = data_dir / "2026-06-27-0806-reddit-radar-raw.json"
    final_digest = reddit_radar_test_digest(final_item)
    final_path.write_text(collector.json.dumps(final_digest, ensure_ascii=False), encoding="utf-8")
    if raw_item is not None:
        raw_path.write_text(
            collector.json.dumps(reddit_radar_test_digest(raw_item), ensure_ascii=False),
            encoding="utf-8",
        )
    return final_path, final_digest


def test_post_file_blocks_missing_computer_use_review(monkeypatch, tmp_path):
    collector = load_collector()
    final_path, _ = write_post_file_pair(tmp_path, collector, final_item=reviewed_reddit_radar_item())

    monkeypatch.setattr(collector, "post_digest", lambda *args, **kwargs: pytest.fail("should not post"))
    monkeypatch.setattr(collector.sys, "argv", ["collect_safari_reddit_humor.py", "--post-file", str(final_path)])
    monkeypatch.setenv("PAVBOT_HUMOR_INGEST_TOKEN", "file-token")

    with pytest.raises(RuntimeError, match="missing raw comment analysis metadata"):
        collector.main()


def test_post_file_blocks_generic_collector_comment_analysis(monkeypatch, tmp_path):
    collector = load_collector()
    final_item = reviewed_reddit_radar_item()
    final_item["whyFunny"] = collector.why_funny_for(final_item["title"], final_item["categoryLabel"])
    final_item["commentHighlights"] = [
        {
            "id": "comment-1",
            "summary": "Najcelniejsza puenta o tym, że sukces wygląda podejrzanie.",
            "explanation": collector.comment_explanation_for(
                "Najcelniejsza puenta o tym, że sukces wygląda podejrzanie.",
                final_item["title"],
                final_item["categoryLabel"],
            ),
            "originalBody": "Najcelniejsza puenta o tym, że sukces wygląda podejrzanie.",
            "score": 88,
        }
    ]
    raw_item = dict(final_item)
    raw_item.update(
        {
            "commentAnalysisStatus": "reviewed",
            "commentAnalysisSource": "codex-computer-use-safari",
            "commentAnalysisNote": "Komentarz obejrzany w Safari.",
        }
    )
    final_path, _ = write_post_file_pair(tmp_path, collector, final_item=final_item, raw_item=raw_item)

    monkeypatch.setattr(collector, "post_digest", lambda *args, **kwargs: pytest.fail("should not post"))
    monkeypatch.setattr(
        collector,
        "publish_reddit_radar_artifacts",
        lambda *args, **kwargs: pytest.fail("should not publish"),
        raising=False,
    )
    monkeypatch.setattr(collector.sys, "argv", ["collect_safari_reddit_humor.py", "--post-file", str(final_path)])
    monkeypatch.setenv("PAVBOT_HUMOR_INGEST_TOKEN", "file-token")

    with pytest.raises(RuntimeError, match="generic"):
        collector.main()


def test_post_file_blocks_comment_highlights_without_ids(monkeypatch, tmp_path):
    collector = load_collector()
    final_item = reviewed_reddit_radar_item()
    for highlight in final_item["commentHighlights"]:
        highlight.pop("id")
    raw_item = dict(final_item)
    raw_item.update(
        {
            "commentAnalysisStatus": "reviewed",
            "commentAnalysisSource": "codex-computer-use-safari",
            "commentAnalysisNote": "Komentarze wybrane po obejrzeniu wątku w Safari.",
        }
    )
    final_path, _ = write_post_file_pair(tmp_path, collector, final_item=final_item, raw_item=raw_item)

    monkeypatch.setattr(collector, "post_digest", lambda *args, **kwargs: pytest.fail("should not post"))
    monkeypatch.setattr(collector.sys, "argv", ["collect_safari_reddit_humor.py", "--post-file", str(final_path)])
    monkeypatch.setenv("PAVBOT_HUMOR_INGEST_TOKEN", "file-token")

    with pytest.raises(RuntimeError, match="comment 1 id is required"):
        collector.main()


def test_post_file_blocks_reviewed_comment_highlights_without_original_body(monkeypatch, tmp_path):
    collector = load_collector()
    final_item = reviewed_reddit_radar_item()
    final_item["commentHighlights"][0].pop("originalBody")
    raw_item = dict(final_item)
    raw_item.update(
        {
            "commentAnalysisStatus": "reviewed",
            "commentAnalysisSource": "codex-computer-use-safari",
            "commentAnalysisNote": "Komentarze wybrane po obejrzeniu wątku w Safari.",
        }
    )
    final_path, _ = write_post_file_pair(tmp_path, collector, final_item=final_item, raw_item=raw_item)

    monkeypatch.setattr(collector, "post_digest", lambda *args, **kwargs: pytest.fail("should not post"))
    monkeypatch.setattr(collector.sys, "argv", ["collect_safari_reddit_humor.py", "--post-file", str(final_path)])
    monkeypatch.setenv("PAVBOT_HUMOR_INGEST_TOKEN", "file-token")

    with pytest.raises(RuntimeError, match="comment 1 originalBody is required"):
        collector.main()


def test_post_file_posts_reviewed_computer_use_analysis(monkeypatch, tmp_path, capsys):
    collector = load_collector()
    final_item = reviewed_reddit_radar_item()
    raw_item = dict(final_item)
    raw_item.update(
        {
            "rawCommentSnippets": [{"body": "Surowy komentarz przeczytany w Safari.", "score": 55}],
            "commentAnalysisStatus": "reviewed",
            "commentAnalysisSource": "codex-computer-use-safari",
            "commentAnalysisNote": "Trzy komentarze wybrane po obejrzeniu wątku w Safari.",
        }
    )
    final_path, final_digest = write_post_file_pair(tmp_path, collector, final_item=final_item, raw_item=raw_item)
    calls = []
    publish_calls = []

    def fake_post_digest(digest, *, notifier_url, token):
        calls.append({"digest": digest, "notifier_url": notifier_url, "token": token})
        return {"status": "stored"}

    monkeypatch.setattr(
        collector,
        "publish_reddit_radar_artifacts",
        lambda *, artifact_root, expected_paths: publish_calls.append(
            {"artifact_root": artifact_root, "expected_paths": expected_paths}
        ),
        raising=False,
    )
    monkeypatch.setattr(collector, "post_digest", fake_post_digest)
    monkeypatch.setattr(
        collector.sys,
        "argv",
        [
            "collect_safari_reddit_humor.py",
            "--post-file",
            str(final_path),
            "--notifier-url",
            "https://notify.example.com",
        ],
    )
    monkeypatch.setenv("PAVBOT_HUMOR_INGEST_TOKEN", "file-token")

    assert collector.main() == 0

    assert len(publish_calls) == 1
    assert publish_calls[0]["artifact_root"] == collector.DEFAULT_ARTIFACT_ROOT
    assert {path.name for path in publish_calls[0]["expected_paths"].values()} == {
        "2026-06-27-0806-reddit-radar.json",
        "2026-06-27-0806-reddit-radar-raw.json",
        "2026-06-27-0806-reddit-radar.md",
    }
    assert calls == [{"digest": final_digest, "notifier_url": "https://notify.example.com", "token": "file-token"}]
    assert "postResult" in capsys.readouterr().out


def test_post_file_posts_no_safe_comments_with_diagnostic_note(monkeypatch, tmp_path):
    collector = load_collector()
    final_item = reviewed_reddit_radar_item()
    final_item["commentHighlights"] = []
    final_item["whyFunny"] = "Ciekawy jest sam kontrast: post ma potencjał do żartu, ale widoczne komentarze nie dawały bezpiecznej puenty do cytowania."
    raw_item = dict(final_item)
    raw_item.update(
        {
            "commentAnalysisStatus": "no_safe_comments",
            "commentAnalysisSource": "codex-computer-use-safari",
            "commentAnalysisNote": "W Safari widoczne były tylko usunięte albo zbyt ryzykowne komentarze.",
        }
    )
    final_path, final_digest = write_post_file_pair(tmp_path, collector, final_item=final_item, raw_item=raw_item)
    calls = []
    publish_calls = []

    monkeypatch.setattr(
        collector,
        "publish_reddit_radar_artifacts",
        lambda *, artifact_root, expected_paths: publish_calls.append(
            {"artifact_root": artifact_root, "expected_paths": expected_paths}
        ),
        raising=False,
    )
    monkeypatch.setattr(
        collector,
        "post_digest",
        lambda digest, *, notifier_url, token: calls.append(digest) or {"status": "stored"},
    )
    monkeypatch.setattr(collector.sys, "argv", ["collect_safari_reddit_humor.py", "--post-file", str(final_path)])
    monkeypatch.setenv("PAVBOT_HUMOR_INGEST_TOKEN", "file-token")

    assert collector.main() == 0

    assert len(publish_calls) == 1
    assert calls == [final_digest]


def test_main_posts_existing_digest_file(monkeypatch, tmp_path, capsys):
    collector = load_collector()
    digest_path = tmp_path / "reddit-radar.json"
    digest_path.write_text(
        collector.json.dumps(
            {
                "id": "humor-test",
                "title": "<RR> Reddit Radar",
                "summary": "Kategorie: dev. Najmocniej wybija się: <u>test</u>.",
                "generatedAt": "2026-06-27T06:06:00+00:00",
                "displayTime": "08:06",
                "nextRefreshAt": "2026-06-27T10:06:00+02:00",
                "refreshIntervalHours": 2,
                "source": "Codex Safari Reddit radar",
                "items": [],
            }
        ),
        encoding="utf-8",
    )
    calls = []

    def fake_post_digest(digest, *, notifier_url, token):
        calls.append({"digest": digest, "notifier_url": notifier_url, "token": token})
        return {"status": "stored"}

    monkeypatch.setattr(collector, "post_digest", fake_post_digest)
    monkeypatch.setattr(
        collector.sys,
        "argv",
        [
            "collect_safari_reddit_humor.py",
            "--post-file",
            str(digest_path),
            "--notifier-url",
            "https://notify.example.com",
        ],
    )
    monkeypatch.setenv("PAVBOT_HUMOR_INGEST_TOKEN", "file-token")

    assert collector.main() == 0

    assert calls == [
        {
            "digest": collector.json.loads(digest_path.read_text(encoding="utf-8")),
            "notifier_url": "https://notify.example.com",
            "token": "file-token",
        }
    ]
    assert "postResult" in capsys.readouterr().out


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
