# Proposal: bootstrap `puls-dnia-news` into public manifest generation

Date: 2026-06-26
Topic: puls-dnia-news
Risk: Medium

## Proposed Change

Add the `puls-dnia-news` topic to the repository state that the isolated publish
worktree uses to generate `public/pavbot-manifest.json`, so that published
`pulseNewsData` artifacts become visible to the iOS app.

This is a one-time bootstrap outside the normal output-only automation scope.
Depending on the current main-branch state, it may require one or more of:

- adding `research/puls-dnia-news/topic.md` and related topic metadata to
  `origin/main`;
- adding the automation/topic references that manifest generation uses for
  discovery;
- adjusting `scripts/generate_pavbot_manifest.py` only if the generator still
  filters out `pulseNewsData` after the topic files exist in the base branch.

## Reason

The 2026-06-26 12:01 run validated and published successfully, but the
generated manifest at pushed commit `e44d7a2` still contains no
`puls-dnia-news` automation, topic, or `pulseNewsData` artifact. The most
likely cause is that the isolated publish worktree starts from `origin/main`
and copies only output files, while the base branch does not yet carry the
topic contract and related bootstrap metadata required by manifest generation.

Without this bootstrap, future `puls-dnia-news` runs can keep producing correct
Markdown and JSON, but the iOS app will not discover them through the public
manifest.

## Files Or Settings Affected

- `research/puls-dnia-news/topic.md`
- `research/puls-dnia-news/automation-prompt.md`
- `docs/how-to-use.md`
- `docs/automation-operations.md`
- `scripts/generate_pavbot_manifest.py`
- potentially `scripts/pavbot_commit_and_push_outputs.sh` if publish bootstrap
  rules need adjustment

## Acceptance Criteria

- `public/pavbot-manifest.json` on `origin/main` lists topic
  `puls-dnia-news`.
- The manifest contains an artifact of type `pulseNewsData` pointing to
  `research/puls-dnia-news/data/YYYY-MM-DD-HHMM-pulse-news.json`.
- The manifest contains the automation/topic metadata needed by the iOS app for
  this topic.
- After the next isolated publish, the iOS app can load at least six pairs of
  cards from the newest `pulseNewsData` artifact.

## Rollback

Revert the bootstrap commit that introduced `puls-dnia-news` into manifest
generation and remove the topic-specific entries from docs or generator logic
if the app integration is postponed.
