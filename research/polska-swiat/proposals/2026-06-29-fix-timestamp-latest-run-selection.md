# Proposal: Fix timestamp latest-run selection

Date: 2026-06-29
Topic: polska-swiat
Risk: Medium

## Proposed Change

Update the publication contract helper so `latest_run()` selects the newest
run by parsed date and optional time, not by raw lexicographic filename order.

## Reason

The evening research automation writes timestamped runs such as
`2026-06-29-1935.md`. When a same-day untimestamped report
`2026-06-29.md` also exists, raw filename sorting treats the untimestamped file
as later than the timestamped evening file. That makes
`scripts/pavbot_publication_contract.py verify-local research/polska-swiat`
print and verify the morning package even when the current run is timestamped.

This run still performs manual verification of the timestamped paths after
publication, but the helper should be corrected before relying on it for
slot-specific or evening publication checks.

## Files Or Settings Affected

- `scripts/pavbot_publication_contract.py`
- Tests covering timestamped and untimestamped run selection, likely in
  `tests/test_pavbot_commit_and_push_outputs.py` or a new focused contract test.

## Acceptance Criteria

- Given `runs/2026-06-29.md` and `runs/2026-06-29-1935.md`, the helper selects
  `2026-06-29-1935.md`.
- Given multiple timestamped files on the same date, the helper selects the
  latest HHMM value.
- Existing date-only topics keep their current behavior.
- Publication verification reports the exact selected package key.

## Rollback

Revert the helper and test change if any topic's publication flow no longer
selects the expected package.
