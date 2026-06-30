#!/usr/bin/env python3
"""Prepare and verify complete Pavbot publication bundles per topic."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
import re


STAMP_RE = re.compile(r"^(?P<date>\d{4}-\d{2}-\d{2})(?:-(?P<time>\d{4}))?")
TOPIC_JOBS = "research/llm-ai-jobs-wroclaw"
TOPIC_TECH = "research/tech-news"
TOPIC_POLSKA = "research/polska-swiat"
TOPIC_MOBILE = "research/aktualne-wydarzenia-mobile"
TOPIC_PULSE = "research/puls-dnia-news"
TOPIC_REDDIT = "research/reddit-radar"


class ContractError(RuntimeError):
    """Raised when a topic bundle is incomplete or cannot be generated."""


@dataclass(frozen=True)
class PublicationBundle:
    topic_path: str
    run_path: Path
    remote_paths: tuple[Path, ...]
    generated_paths: tuple[Path, ...]
    local_required_paths: tuple[Path, ...]
    validator_paths: tuple[Path, ...]
    description: str

    @property
    def stamp(self) -> str:
        return self.run_path.stem

    def relative_remote_paths(self, repo_root: Path) -> list[str]:
        return [str(path.relative_to(repo_root)) for path in self.remote_paths]


def fail(message: str) -> None:
    raise ContractError(message)


def topic_root(repo_root: Path, topic_path: str) -> Path:
    root = repo_root / topic_path
    if not root.is_dir():
        fail(f"missing topic directory: {topic_path}")
    return root


def latest_run(repo_root: Path, topic_path: str, pattern: str = "*.md") -> Path:
    runs_dir = topic_root(repo_root, topic_path) / "runs"
    runs = sorted(path for path in runs_dir.glob(pattern) if path.is_file())
    if not runs:
        fail(f"missing run artifacts in {topic_path}/runs")
    return runs[-1]


def parse_stamp_components(stem: str) -> tuple[str, str | None]:
    match = STAMP_RE.match(stem)
    if not match:
        fail(f"cannot parse run stamp from filename: {stem}")
    run_time = match.group("time")
    if run_time:
        run_time = f"{run_time[:2]}:{run_time[2:]}"
    return match.group("date"), run_time


def ensure_file(path: Path, *, label: str | None = None) -> None:
    if not path.is_file() or path.stat().st_size == 0:
        name = label or path.name
        fail(f"missing required file: {name} -> {path}")


def ensure_any_files(paths: list[Path], *, label: str) -> None:
    if not paths:
        fail(f"missing required file set: {label}")
    for path in paths:
        ensure_file(path)


def needs_refresh(target: Path, sources: tuple[Path, ...]) -> bool:
    if not target.is_file() or target.stat().st_size == 0:
        return True
    target_mtime = target.stat().st_mtime
    return any(source.stat().st_mtime > target_mtime for source in sources if source.exists())


def run_python(repo_root: Path, script: Path, *args: Path | str) -> None:
    cmd = [sys.executable, str(script), *[str(arg) for arg in args]]
    result = subprocess.run(
        cmd,
        cwd=repo_root,
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        details = "\n".join(part for part in (result.stdout.strip(), result.stderr.strip()) if part)
        fail(f"command failed: {' '.join(cmd)}\n{details}".rstrip())


def validate_json(repo_root: Path, validator: Path, payload_path: Path) -> dict:
    run_python(repo_root, validator, payload_path)
    try:
        return json.loads(payload_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        fail(f"invalid JSON after validation for {payload_path}: {exc}")


def check_payload_stamp(payload: dict, run_path: Path) -> None:
    expected_date, expected_time = parse_stamp_components(run_path.stem)
    actual_date = payload.get("runDate")
    actual_time = payload.get("runTime")
    if actual_date != expected_date:
        fail(f"{run_path.name}: runDate mismatch, expected {expected_date}, got {actual_date}")
    if expected_time is not None and actual_time != expected_time:
        fail(f"{run_path.name}: runTime mismatch, expected {expected_time}, got {actual_time}")


def jobs_bundle(repo_root: Path) -> PublicationBundle:
    run_path = latest_run(repo_root, TOPIC_JOBS)
    topic = topic_root(repo_root, TOPIC_JOBS)
    data_path = topic / "data" / f"{run_path.stem}-jobs.json"
    pdf_path = topic / "pdfs" / f"{run_path.stem}-llm-ai-jobs-wroclaw.pdf"
    return PublicationBundle(
        topic_path=TOPIC_JOBS,
        run_path=run_path,
        remote_paths=(run_path, data_path, pdf_path),
        generated_paths=(data_path, pdf_path),
        local_required_paths=(run_path, data_path, pdf_path),
        validator_paths=(data_path,),
        description="run + jobsData + pdf",
    )


def research_bundle(repo_root: Path, topic_path: str, slug: str) -> PublicationBundle:
    run_path = latest_run(repo_root, topic_path)
    topic = topic_root(repo_root, topic_path)
    data_path = topic / "data" / f"{run_path.stem}-research.json"
    pdf_path = topic / "pdfs" / f"{run_path.stem}-{slug}.pdf"
    return PublicationBundle(
        topic_path=topic_path,
        run_path=run_path,
        remote_paths=(run_path, data_path, pdf_path),
        generated_paths=(data_path, pdf_path),
        local_required_paths=(run_path, data_path, pdf_path),
        validator_paths=(data_path,),
        description="run + researchData + pdf",
    )


def mobile_bundle(repo_root: Path) -> PublicationBundle:
    run_path = latest_run(repo_root, TOPIC_MOBILE)
    topic = topic_root(repo_root, TOPIC_MOBILE)
    podcast_dir = topic / "podcasts" / run_path.stem
    data_path = topic / "data" / f"{run_path.stem}-mobile-news.json"
    brief_pdf = topic / "pdfs" / f"{run_path.stem}-mobile-brief.pdf"
    newspaper_pdf = topic / "pdfs" / f"{run_path.stem}-newspaper.pdf"
    script_path = podcast_dir / "script.md"
    audio_paths = tuple(sorted(path for path in podcast_dir.glob("audio/*/podcast.mp3") if path.is_file()))
    if not audio_paths:
        fail(f"missing required audio variant(s) for mobile package {run_path.stem}")
    remote_paths = (data_path, brief_pdf, newspaper_pdf, script_path, *audio_paths)
    return PublicationBundle(
        topic_path=TOPIC_MOBILE,
        run_path=run_path,
        remote_paths=remote_paths,
        generated_paths=(data_path, brief_pdf, newspaper_pdf),
        local_required_paths=(run_path, data_path, brief_pdf, newspaper_pdf, script_path, *audio_paths),
        validator_paths=(data_path,),
        description="run anchor + mobileNewsData + brief/newspaper PDF + script + >=1 mp3",
    )


def pulse_bundle(repo_root: Path) -> PublicationBundle:
    run_path = latest_run(repo_root, TOPIC_PULSE)
    topic = topic_root(repo_root, TOPIC_PULSE)
    data_path = topic / "data" / f"{run_path.stem}-pulse-news.json"
    return PublicationBundle(
        topic_path=TOPIC_PULSE,
        run_path=run_path,
        remote_paths=(run_path, data_path),
        generated_paths=(),
        local_required_paths=(run_path, data_path),
        validator_paths=(data_path,),
        description="run + pulseNewsData",
    )


def reddit_bundle(repo_root: Path) -> PublicationBundle:
    run_path = latest_run(repo_root, TOPIC_REDDIT, pattern="*-reddit-radar.md")
    topic = topic_root(repo_root, TOPIC_REDDIT)
    data_path = topic / "data" / f"{run_path.stem}.json"
    raw_path = topic / "data" / f"{run_path.stem}-raw.json"
    return PublicationBundle(
        topic_path=TOPIC_REDDIT,
        run_path=run_path,
        remote_paths=(run_path, data_path, raw_path),
        generated_paths=(),
        local_required_paths=(run_path, data_path, raw_path),
        validator_paths=(data_path, raw_path),
        description="run + reddit-radar.json + reddit-radar-raw.json",
    )


def bundle_for_topic(repo_root: Path, topic_path: str) -> PublicationBundle:
    if topic_path == TOPIC_JOBS:
        return jobs_bundle(repo_root)
    if topic_path == TOPIC_TECH:
        return research_bundle(repo_root, TOPIC_TECH, "tech-news")
    if topic_path == TOPIC_POLSKA:
        return research_bundle(repo_root, TOPIC_POLSKA, "polska-swiat")
    if topic_path == TOPIC_MOBILE:
        return mobile_bundle(repo_root)
    if topic_path == TOPIC_PULSE:
        return pulse_bundle(repo_root)
    if topic_path == TOPIC_REDDIT:
        return reddit_bundle(repo_root)
    fail(f"unsupported topic contract: {topic_path}")


def prepare_jobs(repo_root: Path, bundle: PublicationBundle) -> None:
    topic = topic_root(repo_root, bundle.topic_path)
    data_path, pdf_path = bundle.generated_paths
    if needs_refresh(data_path, (bundle.run_path,)):
        run_python(
            repo_root,
            topic / "tools" / "render_jobs_data.py",
            bundle.run_path,
            data_path,
        )
    validate_json(repo_root, repo_root / "scripts" / "validate_jobs_data.py", data_path)
    if needs_refresh(pdf_path, (bundle.run_path,)):
        run_python(
            repo_root,
            topic / "tools" / "render_report_pdf.py",
            bundle.run_path,
            pdf_path,
        )


def prepare_research(repo_root: Path, bundle: PublicationBundle, slug: str) -> None:
    data_path, pdf_path = bundle.generated_paths
    if needs_refresh(data_path, (bundle.run_path,)):
        run_python(
            repo_root,
            repo_root / "scripts" / "render_research_data.py",
            bundle.run_path,
            data_path,
            "--topic",
            slug,
        )
    validate_json(repo_root, repo_root / "scripts" / "validate_research_data.py", data_path)
    if needs_refresh(pdf_path, (bundle.run_path,)):
        run_python(
            repo_root,
            repo_root / "scripts" / "render_research_pdf.py",
            bundle.run_path,
            pdf_path,
            "--topic",
            slug,
        )


def prepare_mobile(repo_root: Path, bundle: PublicationBundle) -> None:
    topic = topic_root(repo_root, bundle.topic_path)
    podcast_dir = topic / "podcasts" / bundle.run_path.stem
    data_path, brief_pdf, newspaper_pdf = bundle.generated_paths
    if needs_refresh(data_path, (bundle.run_path,)):
        run_python(
            repo_root,
            repo_root / "scripts" / "render_mobile_news_data.py",
            bundle.run_path,
            data_path,
        )
    validate_json(repo_root, repo_root / "scripts" / "validate_mobile_news_data.py", data_path)
    if needs_refresh(brief_pdf, (bundle.run_path, podcast_dir / "script.md", podcast_dir / "sources.md", podcast_dir / "tts_variants.json")):
        ensure_file(podcast_dir / "script.md", label="mobile script.md")
        ensure_file(podcast_dir / "sources.md", label="mobile sources.md")
        ensure_file(podcast_dir / "tts_variants.json", label="mobile tts_variants.json")
        run_python(
            repo_root,
            topic / "tools" / "render_mobile_brief_pdf.py",
            bundle.run_path,
            podcast_dir,
            brief_pdf,
            "--topic",
            "aktualne-wydarzenia-mobile",
        )
    if needs_refresh(newspaper_pdf, (bundle.run_path,)):
        run_python(
            repo_root,
            topic / "tools" / "render_mobile_newspaper_pdf.py",
            bundle.run_path,
            newspaper_pdf,
            "--topic",
            "aktualne-wydarzenia-mobile",
        )


def prepare_topic(repo_root: Path, topic_path: str) -> PublicationBundle:
    bundle = bundle_for_topic(repo_root, topic_path)
    if topic_path == TOPIC_JOBS:
        prepare_jobs(repo_root, bundle)
    elif topic_path == TOPIC_TECH:
        prepare_research(repo_root, bundle, "tech-news")
    elif topic_path == TOPIC_POLSKA:
        prepare_research(repo_root, bundle, "polska-swiat")
    elif topic_path == TOPIC_MOBILE:
        prepare_mobile(repo_root, bundle)
    elif topic_path in {TOPIC_PULSE, TOPIC_REDDIT}:
        pass
    else:
        fail(f"unsupported prepare topic: {topic_path}")
    print(f"prepared publication bundle for {topic_path}: {bundle.description}")
    return bundle


def verify_jobs_local(repo_root: Path, bundle: PublicationBundle) -> None:
    for path in bundle.local_required_paths:
        ensure_file(path)
    payload = validate_json(repo_root, repo_root / "scripts" / "validate_jobs_data.py", bundle.generated_paths[0])
    check_payload_stamp(payload, bundle.run_path)


def verify_research_local(repo_root: Path, bundle: PublicationBundle) -> None:
    for path in bundle.local_required_paths:
        ensure_file(path)
    payload = validate_json(repo_root, repo_root / "scripts" / "validate_research_data.py", bundle.generated_paths[0])
    check_payload_stamp(payload, bundle.run_path)


def verify_mobile_local(repo_root: Path, bundle: PublicationBundle) -> None:
    for path in bundle.local_required_paths:
        ensure_file(path)
    payload = validate_json(repo_root, repo_root / "scripts" / "validate_mobile_news_data.py", bundle.generated_paths[0])
    check_payload_stamp(payload, bundle.run_path)


def verify_pulse_local(repo_root: Path, bundle: PublicationBundle) -> None:
    for path in bundle.local_required_paths:
        ensure_file(path)
    payload = validate_json(repo_root, repo_root / "scripts" / "validate_pulse_news_data.py", bundle.validator_paths[0])
    check_payload_stamp(payload, bundle.run_path)


def verify_reddit_local(bundle: PublicationBundle) -> None:
    for path in bundle.local_required_paths:
        ensure_file(path)
    for path in bundle.validator_paths:
        try:
            json.loads(path.read_text(encoding="utf-8"))
        except json.JSONDecodeError as exc:
            fail(f"invalid JSON in reddit radar artifact {path}: {exc}")


def verify_local(repo_root: Path, topic_path: str) -> PublicationBundle:
    bundle = bundle_for_topic(repo_root, topic_path)
    if topic_path == TOPIC_JOBS:
        verify_jobs_local(repo_root, bundle)
    elif topic_path in {TOPIC_TECH, TOPIC_POLSKA}:
        verify_research_local(repo_root, bundle)
    elif topic_path == TOPIC_MOBILE:
        verify_mobile_local(repo_root, bundle)
    elif topic_path == TOPIC_PULSE:
        verify_pulse_local(repo_root, bundle)
    elif topic_path == TOPIC_REDDIT:
        verify_reddit_local(bundle)
    else:
        fail(f"unsupported local verification topic: {topic_path}")
    print(f"verified local publication bundle for {topic_path}: {bundle.stamp}")
    return bundle


def git_stdout(repo_root: Path, *args: str) -> str:
    result = subprocess.run(
        ["git", *args],
        cwd=repo_root,
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        details = result.stderr.strip() or result.stdout.strip()
        fail(f"git {' '.join(args)} failed: {details}")
    return result.stdout


def verify_remote(repo_root: Path, topic_path: str, ref: str) -> PublicationBundle:
    bundle = bundle_for_topic(repo_root, topic_path)
    manifest_text = git_stdout(repo_root, "show", f"{ref}:public/pavbot-manifest.json")
    manifest = json.loads(manifest_text)
    manifest_paths = {
        artifact.get("path")
        for artifact in manifest.get("artifacts", [])
        if isinstance(artifact, dict)
    }
    missing_manifest = []
    missing_remote = []
    for rel_path in bundle.relative_remote_paths(repo_root):
        if rel_path not in manifest_paths:
            missing_manifest.append(rel_path)
        result = subprocess.run(
            ["git", "cat-file", "-e", f"{ref}:{rel_path}"],
            cwd=repo_root,
            capture_output=True,
            text=True,
            check=False,
        )
        if result.returncode != 0:
            missing_remote.append(rel_path)

    if missing_manifest or missing_remote:
        messages = []
        if missing_manifest:
            messages.append("missing from remote manifest: " + " ".join(missing_manifest))
        if missing_remote:
            messages.append(f"missing from {ref}: " + " ".join(missing_remote))
        fail("publication verification failed; " + "; ".join(messages))

    print(f"verified remote publication bundle for {topic_path}: {bundle.stamp} on {ref}")
    return bundle


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("prepare", "verify-local", "verify-remote"))
    parser.add_argument("topic_path", help="Topic path like research/llm-ai-jobs-wroclaw")
    parser.add_argument("--repo-root", type=Path, default=Path.cwd())
    parser.add_argument("--ref", default="origin/main", help="Git ref for verify-remote")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    repo_root = args.repo_root.resolve()
    try:
        if args.command == "prepare":
            prepare_topic(repo_root, args.topic_path)
        elif args.command == "verify-local":
            verify_local(repo_root, args.topic_path)
        else:
            verify_remote(repo_root, args.topic_path, args.ref)
    except ContractError as exc:
        print(str(exc), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
