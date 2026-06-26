from pathlib import Path


REQUIRED_PDF_TOPICS = (
    "llm-ai-jobs-wroclaw",
    "tech-news",
    "polska-swiat",
)


def test_research_runs_have_matching_pdf_outputs() -> None:
    repo_root = Path(__file__).resolve().parents[1]
    missing: list[str] = []

    for topic in REQUIRED_PDF_TOPICS:
        topic_root = repo_root / "research" / topic
        for run_path in sorted((topic_root / "runs").glob("*.md")):
            expected_pdf = topic_root / "pdfs" / f"{run_path.stem}-{topic}.pdf"
            if not expected_pdf.is_file():
                missing.append(f"{run_path.relative_to(repo_root)} -> {expected_pdf.relative_to(repo_root)}")

    assert not missing, "Missing research PDFs:\n" + "\n".join(missing)


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
