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
   manifest, waits until changed artifacts are readable from their public raw
   URLs, and then sends APNs alerts for new artifacts and automations.
5. If `PAVBOT_DAILY_WEATHER_ENABLED=true`, the same service fetches Wrocław
   weather every day at 07:30 Europe/Warsaw and sends one APNs weather briefing
   to devices registered with `dailyWeatherEnabled=true`.
6. If `PAVBOT_DAILY_HUMOR_ENABLED=true`, it serves a humor/meme digest for the
   iOS `Dzisiaj` tab from `GET /v1/humor/latest`. In production this can run in
   `PAVBOT_DAILY_HUMOR_SOURCE_MODE=external`, where a local Codex automation
   reads logged-in Safari and publishes the curated digest with
   `POST /v1/humor/digest`.

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

For the `Dzisiaj` humor panel, the preferred local-first setup is Codex + Safari:

```dotenv
PAVBOT_DAILY_HUMOR_SOURCE_MODE=external
PAVBOT_DAILY_HUMOR_INTERVAL_HOURS=2
PAVBOT_HUMOR_INGEST_TOKEN=<long-random-token>
PAVBOT_HUMOR_NOTIFIER_URL=https://notify.example.com
PAVBOT_SAFARI_REDDIT_SUBREDDITS=Polska_wpz,memes,ProgrammerHumor,Polska,technology
```

The local Codex automation runs:

```bash
python3 scripts/collect_safari_reddit_humor.py --max-items 12
```

It uses the logged-in Safari session to read Reddit pages, builds the digest,
writes a local audit package in `research/reddit-radar/`, and then uses
read-only Safari/Computer Use review to prepare the final comment analysis.
The audit package includes raw comment context, local comment-analysis status,
the final digest JSON, and a Polish Markdown summary explaining the selected
comments. The local radar state keeps at most 12 unique posts, adds fresh
non-duplicate finds on every run, and replaces up to 6 oldest posts once the
set is full. It should also check the last 5 days of Reddit Radar outputs and
avoid re-publishing the same Reddit URL or title from recent runs, even after a
post rotates out of the current 12-item state. It must not vote, comment,
share, post, or submit forms on Reddit.

After the generated final JSON and matching raw JSON have per-item
`commentAnalysisStatus` values of `reviewed` or `no_safe_comments`, commit and
push the matching audit package to `origin/main` first and then publish the
digest without re-reading Safari:

```bash
python3 scripts/collect_safari_reddit_humor.py --post-file research/reddit-radar/data/YYYY-MM-DD-HHMM-reddit-radar.json
```

The `--post-file` path now performs the publication guard itself: it commits
and pushes the matching `runs/`, `data/`, and raw JSON package to `origin/main`,
verifies the refreshed manifest, and only then sends the digest to the notifier.
If the current run is missing from `origin/main:public/pavbot-manifest.json`,
treat the publication as incomplete and fix the manifest before reporting
success.

```bash
git fetch origin
git show origin/main:public/pavbot-manifest.json | grep -F "research/reddit-radar/runs/YYYY-MM-DD-HHMM-reddit-radar.md"
```

If you are running the collector directly, the same rule applies: the audit
package must land on `origin/main` before `/v1/humor/latest` is considered a
valid new publication.

The legacy Reddit OAuth mode remains available by setting:

```dotenv
PAVBOT_DAILY_HUMOR_SOURCE_MODE=reddit_oauth
PAVBOT_REDDIT_CLIENT_ID=...
PAVBOT_REDDIT_CLIENT_SECRET=...
PAVBOT_REDDIT_USER_AGENT=PavbotNotifier/1.0 by pavbot
PAVBOT_REDDIT_SUBREDDITS=Polska_wpz,memes,ProgrammerHumor
```

Without an external Codex digest or Reddit OAuth credentials, `/v1/humor/latest`
returns the local fallback. `/status.dailyHumor.sourceMode`,
`/status.dailyHumor.producer`, and `/status.dailyHumor.lastError` explain which
path is active.

Public endpoints:

- `GET /healthz` - lightweight container healthcheck
- `GET /status` - manifest URL, public notifier URL, registered devices, APNs
  configuration status/environment, last valid webhook, last public raw
  readiness gate result, last APNs delivery result, daily weather status, and
  last device registration
- `GET /v1/app/defaults` - public connection defaults for the iOS Settings
  screen: manifest URL, notification server URL, and status URL. This endpoint
  never returns APNs keys, webhook secrets, or Cloudflare credentials.
- `POST /v1/devices` - iOS APNs device registration
- `GET /v1/weather/daily/latest` - latest Wrocław weather briefing for the iOS
  `Dzisiaj` tab
- `GET /v1/humor/latest` - latest curated Reddit humor/meme digest for the iOS
  `Dzisiaj` tab
- `POST /v1/humor/digest` - authenticated Codex Safari ingest endpoint for the
  iOS `Dzisiaj` humor panel
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
PAVBOT_CONTABO_SSH_HOST=contabo \
PAVBOT_CONTABO_BIND_PORT=18082 \
backend/pavbot-notifier/scripts/deploy-contabo.sh
```

The Contabo production variant is intended for `https://notify.paweltanski.com`
behind the server's existing Nginx reverse proxy. It binds the container only on
`127.0.0.1:18082`, caps Docker logs, and keeps `.env` plus APNs `.p8` secrets
server-local. Fill `/opt/pavbot-notifier/.env` from `.env.contabo.example`,
copy the APNs key into `/opt/pavbot-notifier/secrets/`, then rerun the deploy
script with `--start`.

Full guide: `docs/live-ios-notifications-contabo.md`.

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
