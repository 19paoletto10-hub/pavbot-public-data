from __future__ import annotations

from pathlib import Path


def test_reddit_contract_requires_push_before_cloudkit_gate() -> None:
    repo_root = Path(__file__).resolve().parents[1]
    prompt = (repo_root / "research" / "reddit-radar" / "automation-prompt.md").read_text(
        encoding="utf-8"
    )
    lowered = prompt.lower()

    assert "pavbot_commit_and_push_outputs.sh --isolated research/reddit-radar" in prompt
    assert "verify-remote research/reddit-radar --ref origin/main" in prompt
    assert "post" in lowered and "cloudkit" in lowered
    assert lowered.index("pavbot_commit_and_push_outputs.sh") < lowered.index("cloudkit")
    assert "do not commit" not in lowered
    assert "do not push" not in lowered
    assert "nie commituj" not in lowered
    assert "nie pushuj" not in lowered
