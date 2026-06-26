# Pavbot iOS Live Notifier

Docker service for optional iOS live notifications. It receives GitHub webhooks,
fetches the Pavbot manifest, detects new automation files or new automations,
and sends APNs notifications to registered iOS devices.
It can also send one daily Wrocław weather briefing at 07:30 Europe/Warsaw
when daily weather alerts are enabled, refresh weather cache hourly, and keep a
Reddit-only humor/meme digest fresh every 3 hours for the iOS `Dzisiaj` tab.

Live notifications are optional and disabled in the iOS app until a notification
server URL is configured in Settings.

## Flow

1. iOS app asks APNs for a device token.
2. iOS app sends the token to `POST /v1/devices` on this service.
3. GitHub calls `POST /webhooks/github` after repo pushes.
4. The service fetches `PAVBOT_MANIFEST_URL`, compares it with the last stored
   manifest, and sends APNs alerts for new artifacts and automations.
5. If `PAVBOT_DAILY_WEATHER_ENABLED=true`, the same service fetches Wrocław
   weather every day at 07:30 Europe/Warsaw and sends one APNs weather briefing
   to devices registered with `dailyWeatherEnabled=true`.
6. If `PAVBOT_DAILY_HUMOR_ENABLED=true`, it refreshes a Reddit humor/meme digest
   every `PAVBOT_DAILY_HUMOR_INTERVAL_HOURS` hours. This uses Reddit OAuth,
   does not send APNs, and the iOS app reads it from `GET /v1/humor/latest`.

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

For the `Dzisiaj` humor panel, create a Reddit app and set:

```dotenv
PAVBOT_REDDIT_CLIENT_ID=...
PAVBOT_REDDIT_CLIENT_SECRET=...
PAVBOT_REDDIT_USER_AGENT=PavbotNotifier/1.0 by pavbot
PAVBOT_REDDIT_SUBREDDITS=Polska_wpz,memes,ProgrammerHumor
```

Without these Reddit credentials, `/v1/humor/latest` returns the local fallback
and `/status.dailyHumor.lastError` explains that Reddit OAuth is not configured.

Public endpoints:

- `GET /healthz` - lightweight container healthcheck
- `GET /status` - manifest URL, public notifier URL, registered devices, APNs
  configuration status/environment, last valid webhook, last APNs delivery
  result, daily weather status, and last device registration
- `GET /v1/app/defaults` - public connection defaults for the iOS Settings
  screen: manifest URL, notification server URL, and status URL. This endpoint
  never returns APNs keys, webhook secrets, or Cloudflare credentials.
- `POST /v1/devices` - iOS APNs device registration
- `GET /v1/weather/daily/latest` - latest Wrocław weather briefing for the iOS
  `Dzisiaj` tab
- `GET /v1/humor/latest` - latest curated Reddit humor/meme digest for the iOS
  `Dzisiaj` tab
- `POST /webhooks/github` - GitHub push webhook

Full guide: `docs/live-ios-notifications-macbook-cloudflare.md`.

Put the public HTTPS URL of this service into the iOS app:

```text
Settings -> Notification server URL -> Enable file alerts
```

The iOS app also has `Settings -> Przywróć ustawienia domyślne`. It calls
`GET /v1/app/defaults` and fills both the Manifest URL and Notification server
URL from the notifier environment. After changing `PAVBOT_PUBLIC_NOTIFIER_URL`
or `PAVBOT_MANIFEST_URL`, restart the notifier and use that button to refresh
the app settings.

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
- Use `APNS_ENV=sandbox` for Xcode-installed `PavbotViewer` builds and
  `APNS_ENV=production` for TestFlight/App Store builds.
- Use Apple Push Notifications Console with the APNs token copied from the iOS
  app Settings or Diagnostics screen to validate delivery before relying on
  GitHub webhook-driven pushes.

If the iOS app is closed, notifications are delivered only by APNs. Docker,
Cloudflare Tunnel or your VPS, GitHub webhook delivery, and APNs credentials
must all be working; local manifest refreshes inside the app cannot wake a
closed app.
