# Proposal: Repair Verifier Signing Check

Date: 2026-07-08
Topic: polska-swiat
Risk: Medium

## Proposed Change

Align the repository verifier's iOS signing expectation with the current Xcode project state, or deliberately switch the Xcode project signing identity back to the expected distribution identity.

## Reason

During the 2026-07-08 unattended `polska-swiat` research run, `scripts/verify-research-workspace.sh` failed outside the active topic. The failing check expects:

- `CODE_SIGN_IDENTITY = "Apple Distribution";`

The current local Xcode project contains:

- `CODE_SIGN_IDENTITY = "Apple Development";`

This is unrelated to the daily research artifact generation, but it means the repo-wide readiness check cannot be reported as clean.

## Files Or Settings Affected

- `scripts/verify-research-workspace.sh`
- `ios/PavbotViewer/PavbotViewer.xcodeproj/project.pbxproj`
- Potentially signing/export settings used for local development versus release builds

## Acceptance Criteria

- `scripts/verify-research-workspace.sh` exits 0 from a clean working tree.
- The accepted signing identity matches the intended Pavbot Viewer build mode.
- Daily research runs can keep using the verifier without modifying files outside their active topic.

## Rollback

Revert the verifier or Xcode project signing change and rerun `scripts/verify-research-workspace.sh` to confirm the previous behavior is restored.
