import subprocess
from pathlib import Path


SUPPORTED_TOPIC_CONTRACTS = (
    "research/llm-ai-jobs-wroclaw",
    "research/tech-news",
    "research/polska-swiat",
    "research/aktualne-wydarzenia-mobile",
    "research/puls-dnia-news",
    "research/reddit-radar",
)


def test_latest_publication_bundle_contracts_verify_locally() -> None:
    repo_root = Path(__file__).resolve().parents[1]
    helper = repo_root / "scripts" / "pavbot_publication_contract.py"

    for topic_path in SUPPORTED_TOPIC_CONTRACTS:
        result = subprocess.run(
            ["python3", str(helper), "verify-local", topic_path],
            cwd=repo_root,
            capture_output=True,
            text=True,
            check=False,
        )
        assert result.returncode == 0, f"{topic_path}: {result.stderr or result.stdout}"


def test_podcast_generations_have_brief_pdf_outputs() -> None:
    repo_root = Path(__file__).resolve().parents[1]
    missing: list[str] = []

    for topic in ("tech-news", "polska-swiat"):
        podcasts_root = repo_root / "research" / topic / "podcasts"
        for date_dir in sorted(path for path in podcasts_root.iterdir() if path.is_dir()):
            has_generated_output = any(
                (date_dir / name).is_file()
                for name in ("podcast.mp3", "script.md", "render.json", "draft.md", "sources.md")
            )
            if has_generated_output and not (date_dir / "brief.pdf").is_file():
                missing.append(str((date_dir / "brief.pdf").relative_to(repo_root)))

    assert not missing, "Missing podcast brief PDFs:\n" + "\n".join(missing)
