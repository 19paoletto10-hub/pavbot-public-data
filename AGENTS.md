# Agent Instructions

This repository is a local-first research automation workspace.

## Boundaries

- Write research artifacts only inside `research/<topic>/` unless the user asks
  for a repository-wide change.
- Do not modify automation configuration, skill behavior, hooks, MCP config, or
  files outside the active topic as part of an unattended research run.
- For medium-risk or high-risk changes, create a proposal in
  `research/<topic>/proposals/` instead of applying the change.
- Preserve source links in reports. Do not summarize current external facts
  without recording where they came from.

## Report Quality

- Prefer concise Markdown with dated evidence over long narrative.
- Separate new facts from interpretation.
- Include "No material change" when nothing important changed.
- Keep recommendations actionable and scoped.
- Avoid duplicating the same item in consecutive daily reports unless the new
  run adds a material update.

## Verification

- Before claiming the workspace is ready, run `scripts/verify-research-workspace.sh`.
- If a task changes templates or the skill, run the verifier again.
