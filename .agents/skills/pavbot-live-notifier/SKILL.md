---
name: pavbot-live-notifier
description: Set up, debug, and operate Pavbot live notifications and manifest-driven pushes.
---

# Pavbot Live Notifier

Use this skill when Codex is asked to set up, debug, or operate Pavbot live notifications, Cloudflare Tunnel delivery, CloudKit/APNs publishing, or manifest refresh notifications.

## Required Environment

- `PAVBOT_MANIFEST_URL` points to the public Pavbot manifest consumed by the iOS app.
- APNs and App Store Connect credentials must stay outside the repository.
- Cloudflare Tunnel should be used for stable public delivery to the notifier service.

## Workflow

1. Verify the manifest and notification payload contract before publishing.
2. Refresh the CloudKit `cktool` user token immediately before publication with
   `xcrun cktool save-token --type user --method keychain --force`; the shared
   publish script does this automatically unless `PAVBOT_CKTOOL_REFRESH_COMMAND`
   is overridden for tests or local diagnostics.
3. Use `scripts/publish_cloudkit_briefings.py` for CloudKit briefing publication.
4. Use `scripts/pavbot_commit_and_push_outputs.sh` to commit and push generated Pavbot outputs.
5. Run `scripts/verify-research-workspace.sh` before declaring the workspace ready.

## Safety

- Do not commit `.env`, APNs keys, App Store Connect keys, or local tunnel credentials.
- Keep visible alert notifications distinct from silent/background refresh behavior.
