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

## Publication Gate

- A Pavbot automation run that writes app-visible artifacts is not complete
  until the topic outputs and refreshed `public/pavbot-manifest.json` are
  committed and pushed to `origin/main`.
- For slot-based app feeds such as `research/puls-dnia-news`, each scheduled
  slot is a required source check. If the check finds newer material than the
  latest published artifact on `origin/main`, the run must publish a fresh
  topic output plus refreshed manifest in the same cycle.
- Use `scripts/pavbot_commit_and_push_outputs.sh --isolated research/<topic>`
  as the required final publish step.
- The publication script is the only production gate: it refreshes
  `public/pavbot-manifest.json`, publishes topic artifacts to `origin/main`,
  verifies the remote state, and creates/verifies the production CloudKit
  `Briefing`.
- A newer local topic output than the latest remote manifest entry counts as a
  failed or partial publication, not as a successful run.
- If manifest publication, remote verification, or CloudKit publication fails,
  report the run as failed or partially published. Do not describe it as
  finished successfully.
- Manual commands are allowed for diagnostics only, not for finishing
  production publication outside the shared script.
- For app-visible feeds such as Reddit Radar, commit and push the audit
  artifacts and refreshed manifest before CloudKit publication; the iOS app
  must not depend on unpublished local files.

## Verification

- Before claiming the workspace is ready, run `scripts/verify-research-workspace.sh`.
- If a task changes templates or the skill, run the verifier again.
