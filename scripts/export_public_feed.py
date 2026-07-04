#!/usr/bin/env python3
"""Export the app-visible Pavbot feed into a clean public repository tree."""

from __future__ import annotations

import argparse
import json
import shutil
from pathlib import Path
from typing import Any

import generate_pavbot_manifest


FORBIDDEN_PREFIXES = (
    ".agents/",
    "backend/",
    "docs/",
    "integrations/",
    "ios/",
    "scripts/",
    "tests/",
)
FORBIDDEN_BASENAMES = {
    "automation-podcast-prompt.md",
    "automation-prompt.md",
    "automation-research-prompt.md",
    "backlog.md",
    "draft.md",
    "index.md",
    "render.json",
    "sources.md",
    "topic.md",
    "tts_variants.json",
}
FORBIDDEN_SEGMENTS = {"/proposals/", "/tools/"}


def is_forbidden_public_path(path: str) -> bool:
    if path.startswith(FORBIDDEN_PREFIXES):
        return True
    if any(segment in f"/{path}/" for segment in FORBIDDEN_SEGMENTS):
        return True
    return Path(path).name in FORBIDDEN_BASENAMES


def validate_public_manifest(manifest: dict[str, Any]) -> None:
    bad_paths: list[str] = []

    for automation in manifest.get("automations", []):
        if not isinstance(automation, dict):
            continue
        for key in ("sourcePath", "sourceUrl", "outputUrl"):
            value = automation.get(key)
            if isinstance(value, str) and value and is_forbidden_public_path(value):
                bad_paths.append(value)

    for topic in manifest.get("topics", []):
        if not isinstance(topic, dict):
            continue
        for key in ("topicFilePath", "url"):
            value = topic.get(key)
            if isinstance(value, str) and value and is_forbidden_public_path(value):
                bad_paths.append(value)

    for artifact in manifest.get("artifacts", []):
        if not isinstance(artifact, dict):
            continue
        path = artifact.get("path")
        if isinstance(path, str) and is_forbidden_public_path(path):
            bad_paths.append(path)

    if bad_paths:
        formatted = "\n".join(f"  - {path}" for path in sorted(set(bad_paths)))
        raise SystemExit(f"refusing to export developer/private paths:\n{formatted}")


def clear_output_dir(output_dir: Path) -> None:
    output_dir.mkdir(parents=True, exist_ok=True)
    for child in output_dir.iterdir():
        if child.name == ".git":
            continue
        if child.is_dir():
            shutil.rmtree(child)
        else:
            child.unlink()


def copy_manifest_artifacts(repo_root: Path, output_dir: Path, manifest: dict[str, Any]) -> int:
    copied = 0
    for artifact in manifest.get("artifacts", []):
        if not isinstance(artifact, dict):
            continue
        rel_path = artifact.get("path")
        if not isinstance(rel_path, str) or not rel_path:
            continue
        src = repo_root / rel_path
        if not src.is_file():
            raise SystemExit(f"manifest artifact missing on disk: {rel_path}")
        dest = output_dir / rel_path
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src, dest)
        copied += 1
    return copied


def export_public_feed(repo_root: Path, output_dir: Path, raw_base_url: str) -> tuple[dict[str, Any], int]:
    repo_root = repo_root.resolve()
    output_dir = output_dir.resolve()
    if output_dir == repo_root:
        raise SystemExit("output directory must not be the source repository root")

    manifest = generate_pavbot_manifest.build_manifest(
        repo_root,
        raw_base_url=raw_base_url,
        public_feed=True,
    )
    validate_public_manifest(manifest)
    clear_output_dir(output_dir)

    manifest_path = output_dir / "public" / "pavbot-manifest.json"
    manifest_path.parent.mkdir(parents=True, exist_ok=True)
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    copied = copy_manifest_artifacts(repo_root, output_dir, manifest)
    return manifest, copied


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo-root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument(
        "--raw-base-url",
        default="",
        help="Base public raw URL for exported manifest artifact URLs.",
    )
    parser.add_argument(
        "--manifest-url",
        default="",
        help="Public raw manifest URL used to derive --raw-base-url when omitted.",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    try:
        raw_base_url = generate_pavbot_manifest.resolve_raw_base_url(args.raw_base_url, args.manifest_url)
    except ValueError as exc:
        raise SystemExit(f"error: {exc}") from exc

    manifest, copied = export_public_feed(args.repo_root, args.output_dir, raw_base_url)
    print(
        "exported public feed: "
        f"{len(manifest.get('automations', []))} automations, "
        f"{len(manifest.get('topics', []))} topics, "
        f"{copied} artifacts"
    )


if __name__ == "__main__":
    main()
