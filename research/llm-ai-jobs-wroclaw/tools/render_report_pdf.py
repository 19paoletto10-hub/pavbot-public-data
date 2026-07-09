#!/usr/bin/env python3
"""Topic-local wrapper for Pavbot jobs PDF rendering."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(REPO_ROOT / "scripts"))

from render_research_pdf import render_pdf


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("markdown_report", type=Path)
    parser.add_argument("pdf_output", type=Path)
    parser.add_argument("--topic", dest="topic_name", default="llm-ai-jobs-wroclaw")
    args = parser.parse_args()
    render_pdf(args.markdown_report, args.pdf_output, topic_name=args.topic_name)


if __name__ == "__main__":
    main()
