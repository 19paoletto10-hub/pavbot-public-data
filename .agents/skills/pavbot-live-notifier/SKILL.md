---
name: pavbot-live-notifier
description: Use when Codex is asked to set up, debug, verify, or operate Pavbot iOS live notifications, CloudKit briefing publication, APNs registration, or production notification delivery.
---

# Pavbot Live Notifier

Operate Pavbot iOS live notifications through the CloudKit/APNs subscription
flow.

## Read First

1. `AGENTS.md`
2. `docs/CLOUDKIT_MIGRATION.md`
3. `docs/how-to-use.md`
4. `docs/automation-operations.md`

## Workflow

1. Confirm the active manifest URL is the same value in the iOS defaults,
   automation environment, and `Briefing.manifestUrl`.
2. Confirm each active automation finishes by running
   `scripts/pavbot_commit_and_push_outputs.sh --isolated research/<topic>`.
   The script is the only production gate: it pushes topic artifacts plus
   `public/pavbot-manifest.json` to `origin/main`, verifies the remote state,
   publishes one CloudKit `Briefing` for the active topic in
   `iCloud.com.paweltanski.pavbotviewer` / `production` / `SP774TZZU8`, and
   verifies that record before APNs delivery.
3. Confirm local CloudKit credentials and production environment:
   ```bash
   xcrun cktool save-token
   export PAVBOT_CLOUDKIT_CONTAINER_ID=iCloud.com.paweltanski.pavbotviewer
   export PAVBOT_CLOUDKIT_ENVIRONMENT=production
   export PAVBOT_CLOUDKIT_TEAM_ID=SP774TZZU8
   ```
4. Verify the active topic record without publishing unrelated topics:
   ```bash
   scripts/publish_cloudkit_briefings.py verify \
     --manifest public/pavbot-manifest.json \
     --topic research/<topic>
   ```
5. If iOS receives new data but no visible push, inspect:
   - `CloudKitService.createOrUpdateSubscriptions()` for alert title/body,
     sound, desired keys, and `shouldSendContentAvailable`.
   - `ios/PavbotViewer/Sources/PavbotViewer.entitlements` for
     `aps-environment`, CloudKit services, and production CloudKit environment.
   - App Settings/Diagnostics for notification permission, APNs registration
     status, token preview, iCloud availability, and Production APNs label.
6. Validate on a real iPhone/TestFlight/App Store build. Simulator refresh can
   test routing, but it cannot prove production APNs delivery.

## Safety Rules

- Never commit `.env`, APNs `.p8` keys, CloudKit tokens, provisioning profiles,
  or other credentials.
- The repository uses one standard `PavbotViewer` scheme. Keep Push
  Notifications and CloudKit entitlement on the normal Debug/Release build,
  and fix Apple Developer signing/capability issues in Apple’s portal when
  they appear.
- If Apple signing fails with PLA or missing Push Notifications capability,
  report the exact Apple-side action instead of trying to bypass signing.
- Do not use a legacy webhook/notifier as a production channel. Do not
  reintroduce the legacy Docker/FastAPI notifier, GitHub webhook APNs sender,
  Cloudflare Tunnel, Contabo deployment, or `/v1/devices` token registration
  path.

## Verification

Run:

```bash
scripts/verify-research-workspace.sh
python3 -m pytest -q tests/test_publish_cloudkit_briefings.py tests/test_pavbot_commit_and_push_outputs.py
```

For iOS changes, also run the simulator test suite through XcodeBuildMCP.
