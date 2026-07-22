# Proposal: Repair Verifier Settings Copy Check

Date: 2026-07-22
Topic: polska-swiat
Risk: Medium

## Proposed Change

Align `scripts/verify-research-workspace.sh` with the current iOS settings copy, or restore the expected CloudKit notification sentence in `ios/PavbotViewer/Sources/Views/SettingsView.swift`.

## Reason

During the 2026-07-22 unattended `polska-swiat` research run, `scripts/verify-research-workspace.sh` failed outside the active topic. The failing check expects this exact text in `SettingsView.swift`:

- `CloudKit wysyła widoczny alert i sygnał odświeżenia`

The current local file still contains related CloudKit notification UI, but not that exact sentence. This does not affect the daily research report, JSON, or PDF generation, but it prevents a clean repo-wide verifier result.

## Files Or Settings Affected

- `scripts/verify-research-workspace.sh`
- `ios/PavbotViewer/Sources/Views/SettingsView.swift`

## Acceptance Criteria

- `scripts/verify-research-workspace.sh` exits 0 from the current workspace.
- The verifier checks stable UI capability or intentionally required copy, not stale wording.
- Daily research runs can keep using the verifier without modifying files outside their active topic.

## Rollback

Revert the verifier or SettingsView copy change and rerun `scripts/verify-research-workspace.sh` to confirm the previous behavior is restored.
