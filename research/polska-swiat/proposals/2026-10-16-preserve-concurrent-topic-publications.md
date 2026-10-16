# Proposal: Preserve Concurrent Topic Publications

Date: 2026-10-16
Topic: polska-swiat
Risk: Medium

## Proposed Change

Change the isolated publication workflow so that a publisher synchronizes the latest remote topic state immediately before creating its publication commit, then overlays only the manifest-listed outputs from the current job. Add a regression check covering a research package and a podcast package published from separate worktrees for the same topic.

## Reason

The 2026-10-15 research run successfully published the daily Markdown, JSON and PDF in commit `e24f6f41`. A later `polska-swiat` podcast publication from a stale checkout created commit `e4b9ec23`, which preserved the podcast output but removed the three research artifacts and restored older versions of `index.md` and `backlog.md`.

This is a lost-update problem between independent jobs publishing different output classes under the same topic. The current daily run restores the missing 15 October artifacts and merges the topic metadata, but the underlying publisher behavior can recur.

## Files Or Settings Affected

- `scripts/pavbot_commit_and_push_outputs.sh`
- publication manifest generation or merge logic
- tests for isolated concurrent publication
- automation documentation if publication semantics change

## Acceptance Criteria

- A research job and a podcast job started from the same base can publish in either order without deleting the other job's files.
- The publisher stages only its declared outputs plus the regenerated manifest.
- `index.md` and `backlog.md` either merge from the current remote state or use an ownership model that prevents stale replacement.
- The test verifies the final remote tree contains both daily research artifacts and podcast artifacts.
- CloudKit verification and raw GitHub verification still pass after both publications.

## Rollback

Revert the publisher merge change and its tests, restore the previous isolated publication behavior, and republish the latest complete topic state from a clean worktree.
