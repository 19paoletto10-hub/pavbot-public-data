# Proposal: publish-verifier-filter-non-app-artifacts

Date: 2026-06-28
Topic: tech-news
Risk: Medium

## Proposed Change

Update `scripts/pavbot_commit_and_push_outputs.sh` so remote publication
verification checks only app-visible/generated manifest artifacts for the active
topic. The verifier should ignore `.gitkeep`, `.DS_Store`, and duplicate local
artifact copies such as files with ` 2` suffixes when those files are not
intended to appear in `public/pavbot-manifest.json`.

## Reason

The 2026-06-28 tech-news publication pushed the current report, research JSON,
PDF, index/backlog updates, and refreshed manifest to `origin/main`. Manual
remote verification confirmed the current run paths in
`origin/main:public/pavbot-manifest.json` and confirmed those paths exist on
`origin/main`.

The publish script still exited nonzero because its generic verifier compared
every file under topic output directories against the manifest, including
non-app-visible housekeeping files and duplicate local copies. That can make a
valid current package look failed and can recur in unattended automation runs.

## Files Or Settings Affected

- `scripts/pavbot_commit_and_push_outputs.sh`
- Potentially tests covering publication verification behavior.

## Acceptance Criteria

- `scripts/pavbot_commit_and_push_outputs.sh --isolated --force-manifest research/tech-news`
  succeeds when the current package paths are present in the manifest and on
  `origin/main`.
- Verification still fails when the current run Markdown, current research JSON,
  current PDF, or refreshed manifest is missing remotely.
- The verifier ignores `.gitkeep`, `.DS_Store`, and duplicate local Finder-style
  copies that are not emitted by `scripts/generate_pavbot_manifest.py`.
- Existing publication safeguards still prevent commits outside the allowed
  topic output paths and `public/pavbot-manifest.json`.

## Rollback

Revert the verifier changes and restore the current behavior of checking every
file under the active topic's output directories against the remote manifest.
