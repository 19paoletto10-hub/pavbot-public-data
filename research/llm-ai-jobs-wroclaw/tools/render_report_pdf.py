#!/usr/bin/env python3
"""Render the LLM/AI jobs Markdown report to a premium mobile PDF."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(REPO_ROOT / "scripts"))

from render_research_pdf import render_pdf as render_research_pdf  # noqa: E402


def render_pdf(markdown_path: Path, pdf_path: Path) -> None:
    render_research_pdf(markdown_path, pdf_path, topic_name="llm-ai-jobs-wroclaw")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("markdown_report", type=Path)
    parser.add_argument("pdf_output", type=Path)
    args = parser.parse_args()
    render_pdf(args.markdown_report, args.pdf_output)


if __name__ == "__main__":
    main()
