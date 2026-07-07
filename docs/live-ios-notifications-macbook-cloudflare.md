# Live iOS Notifications With MacBook And Cloudflare Tunnel

Pavbot live iOS notifications are an optional add-on. They stay disabled in
the iOS app until the user enters a notification server URL and enables alerts.

This variant runs the notifier on your MacBook with Docker and exposes it
through Cloudflare Tunnel. Cloudflare Tunnel keeps an outbound-only connection
from `cloudflared` to Cloudflare, so the MacBook does not need public inbound
ports or router port forwarding.

## Architecture

1. Docker runs `backend/pavbot-notifier` locally on `http://localhost:8080`.
2. `cloudflared` exposes that local service as public HTTPS, for example
   `https://notify.example.com`.
3. GitHub sends `push` webhooks to
   `https://notify.example.com/webhooks/github`.
4. Each Codex automation publishes its topic with
   `scripts/pavbot_commit_and_push_outputs.sh --isolated research/<topic>`, which refreshes
   `public/pavbot-manifest.json` and pushes it to `origin/main`.
5. The notifier fetches `PAVBOT_MANIFEST_URL`, diffs it against the last stored
   manifest, and sends APNs alerts for new files or newly enabled automations.
6. The iOS app registers the APNs device token with
   `POST https://notify.example.com/v1/devices`.
7. Tapping a notification opens the generated artifact or the Automations tab.

The MacBook must be awake and online. If the MacBook sleeps, GitHub webhooks
cannot reach the local notifier until the tunnel reconnects.

## Required Accounts And Keys

- Cloudflare account with a domain routed through Cloudflare.
- GitHub repository that stores `public/pavbot-manifest.json`.
- Apple Developer account with Push Notifications enabled for
  `com.paweltanski.pavbotviewer`.
- APNs `.p8` auth key.

True iPhone remote push alerts require a push-enabled iOS build. The checked-in
Xcode project now uses one standard `PavbotViewer` scheme with Push
Notifications enabled in Debug and Release. If signing fails, fix the Apple
Developer account first: accept any pending PLA update and enable Push
Notifications for Bundle ID `com.paweltanski.pavbotviewer`.

## Closed-App Delivery

When the iOS app is closed, it cannot poll GitHub or create local catch-up
notifications. Closed-app alerts only work through this live path:

```text
Codex automation -> Git commit/push -> GitHub webhook -> pavbot-notifier -> APNs -> iPhone
```

If Docker, Cloudflare Tunnel, GitHub webhook delivery, APNs credentials, or the
MacBook are offline, the iPhone will not receive a push while the app is
closed. The app will still refresh files on demand after it is opened.

## Local Docker Setup

```bash
cd backend/pavbot-notifier
cp .env.example .env
mkdir -p secrets
# copy AuthKey_XXXX.p8 into ./secrets/
docker compose up -d --build
curl http://localhost:8080/healthz
curl http://localhost:8080/status
```

## One-Click MacBook Start

For day-to-day use, open these files in Finder:

```text
backend/pavbot-notifier/Start Pavbot Notifier.command
backend/pavbot-notifier/Status Pavbot Notifier.command
```

`Start Pavbot Notifier.command` checks Docker, creates `.env` from
`.env.example` on first run, opens the local `secrets/` folder for the APNs key,
starts `docker compose up -d --build`, and starts `cloudflared` when
`~/.cloudflared/pavbot-notifier.yml` exists. `Status Pavbot Notifier.command`
opens the local or public `/status` endpoint.

The first run cannot be fully automatic because APNs and Cloudflare credentials
must stay local and must never be committed. After `.env`, the APNs `.p8` key,
and Cloudflare tunnel config are ready, the start file is the normal one-click
launcher.

Set these values in `.env`:

```dotenv
PAVBOT_MANIFEST_URL=https://raw.githubusercontent.com/<owner>/<repo>/<branch>/public/pavbot-manifest.json
PAVBOT_PUBLIC_NOTIFIER_URL=https://notify.example.com
GITHUB_WEBHOOK_SECRET=change-me
APNS_ENV=sandbox
APNS_TEAM_ID=SP774TZZU8
APNS_KEY_ID=<APPLE_APNS_KEY_ID>
APNS_BUNDLE_ID=com.paweltanski.pavbotviewer
APNS_PRIVATE_KEY_PATH=/run/secrets/AuthKey_<APPLE_APNS_KEY_ID>.p8
PAVBOT_DAILY_WEATHER_ENABLED=true
PAVBOT_DAILY_WEATHER_TIME=07:30
PAVBOT_DAILY_WEATHER_TIMEZONE=Europe/Warsaw
PAVBOT_DAILY_WEATHER_CITY=Wrocław
PAVBOT_DAILY_WEATHER_LAT=51.1079
PAVBOT_DAILY_WEATHER_LON=17.0385
```

Use `APNS_ENV=sandbox` for Xcode-installed `PavbotViewer` builds. Use
`APNS_ENV=production` for TestFlight/App Store builds.

## Cloudflare Tunnel Setup

Official Cloudflare references:

- [Cloudflare Tunnel overview](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/)
- [Create a locally-managed tunnel](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/do-more-with-tunnels/local-management/create-local-tunnel/)
- [Tunnel configuration file](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/do-more-with-tunnels/local-management/configuration-file/)

Install and authenticate `cloudflared`:

```bash
brew install cloudflared
cloudflared tunnel login
cloudflared tunnel create pavbot-notifier
```

Create `~/.cloudflared/pavbot-notifier.yml` from
`backend/pavbot-notifier/cloudflare/config.example.yml`:

```yaml
tunnel: <Tunnel-UUID>
credentials-file: /Users/<you>/.cloudflared/<Tunnel-UUID>.json

ingress:
  - hostname: notify.example.com
    service: http://localhost:8080
  - service: http_status:404
```

Route DNS and run the tunnel:

```bash
cloudflared tunnel route dns pavbot-notifier notify.example.com
cloudflared tunnel --config ~/.cloudflared/pavbot-notifier.yml run pavbot-notifier
```

Check the public endpoint:

```bash
curl https://notify.example.com/healthz
curl https://notify.example.com/status
```

The `/status` response is the source of truth for push diagnostics. It reports
`registeredDevices`, `apnsConfigured`, `apnsEnvironment`, `lastWebhook`,
`lastApnsDelivery`, `dailyWeather`, and `lastDeviceRegistration`.

The iOS Settings screen can restore the current connection defaults from the
notifier:

```bash
curl https://notify.example.com/v1/app/defaults
```

That endpoint returns only public values: the GitHub raw manifest URL, the
public notification server URL, and the `/status` URL. It is the source of
truth for the app button `Przywróć ustawienia domyślne`; it does not expose
APNs keys, webhook secrets, Cloudflare tokens, or other private configuration.

## Daily Wrocław Weather Alerts

The notifier can send one weather briefing every day at 07:30 Europe/Warsaw.
The iOS app shows it in the `Dzisiaj` tab after the user taps the push.

Requirements:

- Docker notifier and Cloudflare Tunnel must be running at 07:30.
- `.env` must have `PAVBOT_DAILY_WEATHER_ENABLED=true`.
- The iOS device must be registered with live alerts and `Daily Wrocław weather
  alerts` enabled in Settings.
- TestFlight/App Store builds require `APNS_ENV=production`.

Check status:

```bash
curl https://notify.example.com/status
curl https://notify.example.com/v1/weather/daily/latest
```

The weather report uses Open-Meteo for forecast data and a local Polish
nameday calendar bundled into the notifier.

## Temporary Quick Tunnel Reset

Use this only when there is no named Cloudflare tunnel/domain yet, or when a
previous `*.trycloudflare.com` URL returns `530` or no longer resolves.
Quick Tunnel URLs are temporary and change every time the tunnel is recreated.

Run the tunnel from an interactive Terminal window so it stays alive:

```bash
cd /Users/promaczek/Documents/CODEX-Pavbot
cloudflared tunnel --url http://localhost:8080 --protocol http2 --no-autoupdate
```

Copy the new `https://<random>.trycloudflare.com` URL, then set the same host in
three places:

```dotenv
PAVBOT_PUBLIC_NOTIFIER_URL=https://<random>.trycloudflare.com
```

```text
iOS Settings -> Notification server URL -> https://<random>.trycloudflare.com
GitHub webhook -> https://<random>.trycloudflare.com/webhooks/github
```

Restart the notifier after changing `.env`:

```bash
docker compose -f backend/pavbot-notifier/docker-compose.yml up -d
curl https://<random>.trycloudflare.com/status
curl https://<random>.trycloudflare.com/v1/app/defaults
```

Keep the Terminal window open. Closing it stops the tunnel and closed-app iPhone
push notifications will stop until a new tunnel URL is configured.

After the notifier is restarted, open the app and tap
`Ustawienia -> Przywróć ustawienia domyślne`. The app will refill the Manifest
URL and Notification server URL from `/v1/app/defaults`. If the old URL in the
text box is already broken, the app falls back to its bundled bootstrap notifier
URL. For App Store releases, prefer a named Cloudflare tunnel/domain so the
bundled bootstrap URL does not need to change after every Quick Tunnel reset.

## Start After MacBook Restart

After `.env` and `~/.cloudflared/pavbot-notifier.yml` are ready:

```bash
backend/pavbot-notifier/scripts/install-macbook-launchd.sh
```

This installs two user LaunchAgents:

- `com.pavbot.notifier` starts `docker compose up -d --build`;
- `com.pavbot.cloudflared` starts the Cloudflare tunnel if
  `~/.cloudflared/pavbot-notifier.yml` exists.

Logs:

```bash
tail -f /tmp/com.pavbot.notifier.err.log
tail -f /tmp/com.pavbot.cloudflared.err.log
```

## GitHub Webhook

In your GitHub repository settings, add a webhook:

- Payload URL: `https://notify.example.com/webhooks/github`
- Content type: `application/json`
- Secret: same value as `GITHUB_WEBHOOK_SECRET`
- Event: `push`

The notifier status endpoint shows the last valid webhook:

```bash
curl https://notify.example.com/status
```

If the iOS app does not show a new automation, check:

- the Codex automation committed artifacts and refreshed
  `public/pavbot-manifest.json` by running
  `scripts/pavbot_commit_and_push_outputs.sh --isolated research/<topic>`;
- GitHub webhook delivery succeeded;
- `/status` shows the expected `lastWebhook`;
- `registeredDevices` is greater than `0`;
- `PAVBOT_MANIFEST_URL` matches the Manifest URL in iOS Settings.

## iOS App Setup

In the app:

```text
Settings -> Notification server URL
```

Enter the public Cloudflare URL, for example:

```text
https://notify.example.com
```

Then choose `Enable file alerts`.

If the notification server URL is empty, the app should route the user to
Settings and should not show the system APNs permission prompt yet.

## Apple Push Notifications Console Smoke Test

Open the Apple Push Notifications Console for this app:

```text
https://icloud.developer.apple.com/dashboard/notifications/teams/SP774TZZU8/app/com.paweltanski.pavbotviewer/notifications/create
```

Use these values:

- Environment: `Development` for Xcode-installed `PavbotViewer`; `Production`
  only for TestFlight/App Store builds.
- Recipient: copy the APNs device token from Pavbot iOS
  `Settings -> Copy APNs device token` or `Diagnostics -> Copy APNs device token`.
- `apns-topic`: `com.paweltanski.pavbotviewer`
- `apns-push-type`: `alert`
- `apns-priority`: `High (10)`
- Expiration: `Attempt delivery once`

Smoke payload:

```json
{
  "aps": {
    "alert": {
      "title": "Pavbot",
      "subtitle": "Nowy plik",
      "body": "Wykryto nowy artefakt automatyzacji."
    },
    "sound": "default"
  },
  "artifactID": "research/tech-news/runs/2026-06-22.md",
  "artifactPath": "research/tech-news/runs/2026-06-22.md",
  "manifestURL": "https://raw.githubusercontent.com/19paoletto10-hub/pavbot-public-data/main/public/pavbot-manifest.json"
}
```

Do not enable Broadcast or Channels for Pavbot v1. New-file notifications use
normal device-token alert pushes.

## Push Notifications Build

Default scheme:

- `PavbotViewer`
- includes `Sources/PavbotViewer.entitlements`
- use after accepting any Apple PLA update and enabling Push Notifications
  for Bundle ID `com.paweltanski.pavbotviewer`
- Apple Team ID: `SP774TZZU8`
