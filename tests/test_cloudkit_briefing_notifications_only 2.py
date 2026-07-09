from __future__ import annotations

from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]


def test_cloudkit_briefing_automation_prompts_do_not_require_backend_notification_trigger():
    checked_paths = sorted((REPO_ROOT / "research").glob("*/automation*prompt.md"))
    assert checked_paths

    forbidden = [
        "pavbot_notify_ios_after_publish.py",
        "/v1/notifications/manifest-changes",
        "PAVBOT_NOTIFICATION_TRIGGER_TOKEN",
    ]
    violations: list[str] = []
    for path in checked_paths:
        text = path.read_text(encoding="utf-8")
        for snippet in forbidden:
            if snippet in text:
                violations.append(f"{path.relative_to(REPO_ROOT)}: {snippet}")

    assert violations == []


def test_cloudkit_briefing_docs_describe_cloudkit_subscription_without_backend_trigger():
    checked_paths = [
        REPO_ROOT / "docs" / "how-to-use.md",
        REPO_ROOT / "backend" / "pavbot-notifier" / "README.md",
        REPO_ROOT / "scripts" / "verify-research-workspace.sh",
    ]
    forbidden = [
        "pavbot_notify_ios_after_publish.py",
        "/v1/notifications/manifest-changes",
        "PAVBOT_NOTIFICATION_TRIGGER_TOKEN",
    ]
    violations: list[str] = []
    for path in checked_paths:
        text = path.read_text(encoding="utf-8")
        for snippet in forbidden:
            if snippet in text:
                violations.append(f"{path.relative_to(REPO_ROOT)}: {snippet}")

    assert violations == []
