# Live iOS Notifications With Contabo/VPS

Pavbot live iOS notifications are an optional add-on. They are disabled by
default in the app and only start after the user enters a notification server
URL in `Settings` and grants notification permission.

The recommended low-cost local-hosted option is now
`docs/live-ios-notifications-macbook-cloudflare.md`. Use this Contabo/VPS guide
when you want the notification service to stay online without depending on a
MacBook being awake.

## Architecture

- GitHub sends a `push` webhook to the Contabo Docker service.
- Each Codex automation must first run
  `scripts/pavbot_commit_and_push_outputs.sh research/<topic>` to push its
  artifacts and refreshed `public/pavbot-manifest.json` to GitHub.
- The service fetches `PAVBOT_MANIFEST_URL` with no-cache headers.
- It compares the new manifest with the last stored manifest.
- It sends APNs alerts for new artifacts and newly enabled automations.
- Tapping an artifact notification opens the artifact view in the iOS app.
- Tapping an automation notification opens the Automations tab.

## Deploy

1. Copy `backend/pavbot-notifier/` to the Contabo server.
2. Create `.env` from `.env.example`.
3. Put the Apple APNs `.p8` key in `backend/pavbot-notifier/secrets/`.
4. Start the service:

```bash
docker compose up -d --build
```

5. Configure a GitHub webhook:
   - Payload URL: `https://<domain>/webhooks/github`
   - Content type: `application/json`
   - Secret: same as `GITHUB_WEBHOOK_SECRET`
   - Event: `push`

6. In the iOS app, set:

```text
Settings -> Notification server URL -> Enable file alerts
```

## Required Secrets

- `PAVBOT_MANIFEST_URL`
- `GITHUB_WEBHOOK_SECRET`
- `APNS_TEAM_ID`
- `APNS_KEY_ID`
- `APNS_BUNDLE_ID`
- `APNS_PRIVATE_KEY_PATH`
- `APNS_ENV=sandbox|production`

Use `APNS_TEAM_ID=SP774TZZU8` for `com.paweltanski.pavbotviewer`. Use
`APNS_ENV=sandbox` for Xcode-installed `PavbotViewerPush` builds and
`APNS_ENV=production` for TestFlight/App Store builds.

## Apple Developer Setup

The checked-in Xcode project keeps Push Notifications disabled by default so it
can build with a normal automatic signing profile. When you are ready to enable
the optional live notification add-on:

- accept any pending Apple Developer Program License Agreement in the Apple
  Developer account;
- enable Push Notifications for Bundle ID `com.paweltanski.pavbotviewer`;
- use the push-enabled `PavbotViewerPush` scheme in Xcode;
- copy the APNs token from Pavbot iOS Settings or Diagnostics when testing in
  Apple Push Notifications Console;
- keep `APNS_ENV=sandbox` for development builds and use `production` for
  TestFlight/App Store builds.
