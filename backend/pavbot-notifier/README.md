# Pavbot iOS Live Notifier

Docker service for optional iOS live notifications. It receives GitHub webhooks,
fetches the Pavbot manifest, detects new automation files or new automations,
and sends APNs notifications to registered iOS devices.

Live notifications are optional and disabled in the iOS app until a notification
server URL is configured in Settings.

## Flow

1. iOS app asks APNs for a device token.
2. iOS app sends the token to `POST /v1/devices` on this service.
3. GitHub calls `POST /webhooks/github` after repo pushes.
4. The service fetches `PAVBOT_MANIFEST_URL`, compares it with the last stored
   manifest, and sends APNs alerts for new artifacts and automations.

## MacBook + Cloudflare Tunnel Deploy

The recommended low-cost setup is to run this service on your MacBook and
publish it with Cloudflare Tunnel:

One-click launcher:

```text
Start Pavbot Notifier.command
Status Pavbot Notifier.command
```

Double-click `Start Pavbot Notifier.command` in Finder after `.env`, the APNs
`.p8` key, and Cloudflare tunnel config are ready. On first run it creates
`.env` from `.env.example` and opens the files you need to fill.

```bash
cd backend/pavbot-notifier
cp .env.example .env
mkdir -p secrets
# copy your Apple AuthKey_XXXX.p8 into ./secrets/
docker compose up -d --build
cloudflared tunnel --config ~/.cloudflared/pavbot-notifier.yml run pavbot-notifier
```

Public endpoints:

- `GET /healthz` - lightweight container healthcheck
- `GET /status` - manifest URL, public notifier URL, registered devices, APNs
  configuration status, and last valid webhook
- `POST /v1/devices` - iOS APNs device registration
- `POST /webhooks/github` - GitHub push webhook

Full guide: `docs/live-ios-notifications-macbook-cloudflare.md`.

Put the public HTTPS URL of this service into the iOS app:

```text
Settings -> Notification server URL -> Enable file alerts
```

GitHub webhook:

- Payload URL: `https://<cloudflare-domain>/webhooks/github`
- Content type: `application/json`
- Secret: same as `GITHUB_WEBHOOK_SECRET`
- Events: `push`

## Contabo/VPS Deploy

```bash
scp -r backend/pavbot-notifier user@contabo:/opt/pavbot-notifier
ssh user@contabo
cd /opt/pavbot-notifier
cp .env.example .env
mkdir -p secrets
# copy your Apple AuthKey_XXXX.p8 into ./secrets/
docker compose up -d --build
```

## Required Apple Setup

- Bundle ID `com.paweltanski.pavbotviewer` must have Push Notifications enabled.
- Create an APNs Auth Key in Apple Developer.
- Set `APNS_TEAM_ID=SP774TZZU8`, `APNS_KEY_ID`, `APNS_BUNDLE_ID`, and
  `APNS_PRIVATE_KEY_PATH`.
- Use `APNS_ENV=sandbox` for Xcode-installed `PavbotViewerPush` builds and
  `APNS_ENV=production` for TestFlight/App Store builds.
- Use Apple Push Notifications Console with the APNs token copied from the iOS
  app Settings or Diagnostics screen to validate delivery before relying on
  GitHub webhook-driven pushes.
