# Live iOS Notifications With Contabo/VPS

Pavbot live iOS notifications can run on Contabo as the production notifier
host. This is the preferred setup when notifications should work 24/7 without
depending on a MacBook, a local Docker daemon, or a temporary Cloudflare Quick
Tunnel.

This repository keeps the MacBook setup as a development/backup path. The
Contabo path is isolated so it can share a server with other applications.

## Production Endpoint

Recommended public URL:

```text
https://notify.paweltanski.com
```

The service itself must stay private on localhost:

```text
127.0.0.1:18082 -> pavbot-notifier:8080
```

Do not expose container port `8080` directly to the internet. GitHub, iOS, and
APNs-facing diagnostics should only use HTTPS on `notify.paweltanski.com`.

## Architecture

- Codex automations publish artifacts and `public/pavbot-manifest.json` to
  `origin/main`.
- GitHub sends one `push` webhook to
  `https://notify.paweltanski.com/webhooks/github`.
- The Contabo notifier fetches `PAVBOT_MANIFEST_URL`, diffs the manifest, and
  sends APNs alerts for new artifacts.
- The iOS app registers device tokens with
  `POST https://notify.paweltanski.com/v1/devices`.
- The app can restore connection defaults from
  `GET https://notify.paweltanski.com/v1/app/defaults`.

Use only one active webhook destination for production. Running MacBook and
Contabo webhooks at the same time can send duplicate notifications to the same
device.

## Server Safety Rules

This server hosts other applications. Before starting Pavbot:

- check free disk space with `df -h /`;
- check Docker storage with `docker system df`;
- check active ports with `docker ps` and `ss -ltnp`;
- keep Pavbot on `127.0.0.1:18082` unless that port is busy;
- keep Docker logs capped at `10m x 3`;
- keep secrets only in `/opt/pavbot-notifier/secrets/`.

The deploy helper blocks startup when available disk is below
`PAVBOT_CONTABO_MIN_FREE_MB` (default `4096` MB). If the server is almost full,
review Docker build cache and unused images manually before deploying.

## Files

- `backend/pavbot-notifier/docker-compose.yml` - base Docker service.
- `backend/pavbot-notifier/docker-compose.contabo.yml` - Contabo override:
  local-only bind, log caps, stable compose project name.
- `backend/pavbot-notifier/.env.contabo.example` - production template for
  `notify.paweltanski.com`.
- `backend/pavbot-notifier/nginx/notify.paweltanski.com.conf` - Nginx vhost
  example for HTTPS reverse proxy.
- `backend/pavbot-notifier/scripts/contabo-preflight.sh` - server-side safety
  check.
- `backend/pavbot-notifier/scripts/deploy-contabo.sh` - rsync-based code deploy
  that does not overwrite `.env` or `secrets/`.

## Deploy Code

From the MacBook workspace:

```bash
PAVBOT_CONTABO_SSH_HOST=contabo \
PAVBOT_CONTABO_BIND_PORT=18082 \
backend/pavbot-notifier/scripts/deploy-contabo.sh
```

This copies code to `/opt/pavbot-notifier`, creates `.env` from
`.env.contabo.example` only if it does not exist, and validates Docker Compose.
It does not start the service unless `--start` is passed.

After `.env` and secrets are ready:

```bash
PAVBOT_CONTABO_SSH_HOST=contabo \
PAVBOT_CONTABO_BIND_PORT=18082 \
backend/pavbot-notifier/scripts/deploy-contabo.sh --start
```

On the server, the equivalent command is:

```bash
cd /opt/pavbot-notifier
PAVBOT_CONTABO_BIND_PORT=18082 \
docker compose -p pavbot-notifier \
  -f docker-compose.yml \
  -f docker-compose.contabo.yml \
  up -d --build
```

## Required `.env`

Create `/opt/pavbot-notifier/.env` from `.env.contabo.example` and fill the
secret values:

```dotenv
PAVBOT_MANIFEST_URL=https://raw.githubusercontent.com/19paoletto10-hub/pavbot-public-data/main/public/pavbot-manifest.json
PAVBOT_PUBLIC_NOTIFIER_URL=https://notify.paweltanski.com
PAVBOT_CONTABO_BIND_PORT=18082
GITHUB_WEBHOOK_SECRET=...
APNS_ENV=production
APNS_TEAM_ID=SP774TZZU8
APNS_KEY_ID=...
APNS_BUNDLE_ID=com.paweltanski.pavbotviewer
APNS_PRIVATE_KEY_PATH=/run/secrets/AuthKey_<APNS_KEY_ID>.p8
PAVBOT_DAILY_HUMOR_ENABLED=true
PAVBOT_DAILY_HUMOR_SOURCE_MODE=external
PAVBOT_DAILY_HUMOR_INTERVAL_HOURS=2
PAVBOT_HUMOR_INGEST_TOKEN=<long-random-token>
```

Use `APNS_ENV=production` for TestFlight/App Store. Use `sandbox` only for
debug builds installed directly from Xcode.

Copy the APNs key to:

```text
/opt/pavbot-notifier/secrets/AuthKey_<APNS_KEY_ID>.p8
```

Then lock permissions:

```bash
chmod 600 /opt/pavbot-notifier/.env
chown 10001:10001 /opt/pavbot-notifier/secrets/AuthKey_<APNS_KEY_ID>.p8
chmod 600 /opt/pavbot-notifier/secrets/AuthKey_<APNS_KEY_ID>.p8
```

For `Dzisiaj -> Śmiechowy radar`, use the same
`PAVBOT_HUMOR_INGEST_TOKEN` in the local MacBook
`backend/pavbot-notifier/.env`. The Codex automation reads Reddit through the
logged-in Safari profile and publishes to:

```bash
python3 scripts/collect_safari_reddit_humor.py --post
```

The Docker image runs as `appuser` with UID `10001`. If the APNs key remains
`root:root` with mode `600`, APNs sends will fail with `Permission denied`
inside the container.

## Nginx

Install the vhost without changing the existing `paweltanski.com` site:

```bash
cp /opt/pavbot-notifier/nginx/notify.paweltanski.com.conf \
  /etc/nginx/sites-available/notify.paweltanski.com.conf
ln -sfn /etc/nginx/sites-available/notify.paweltanski.com.conf \
  /etc/nginx/sites-enabled/notify.paweltanski.com.conf
```

Create the certificate:

```bash
certbot certonly --webroot \
  -w /var/www/paweltanski/webroot \
  -d notify.paweltanski.com
```

Then validate and reload:

```bash
nginx -t
systemctl reload nginx
```

## GitHub And iOS Cutover

GitHub webhook:

```text
Payload URL: https://notify.paweltanski.com/webhooks/github
Content type: application/json
Secret: same as GITHUB_WEBHOOK_SECRET
Events: push
```

iOS:

```text
Settings -> Notification server URL -> https://notify.paweltanski.com
Settings -> Enable file alerts
```

If the app still has an old temporary tunnel URL, use:

```text
Settings -> Przywróć ustawienia domyślne
```

This calls `/v1/app/defaults` and fills the current manifest and notifier URLs
from the Contabo `.env`.

## Verification

On the server:

```bash
curl http://127.0.0.1:18082/healthz
curl http://127.0.0.1:18082/status
```

Publicly:

```bash
curl https://notify.paweltanski.com/healthz
curl https://notify.paweltanski.com/status
curl https://notify.paweltanski.com/v1/app/defaults
```

Expected `/status` after iOS registration:

- `apnsConfigured: true`
- `apnsEnvironment: production`
- `registeredDevices >= 1`
- `publicNotifierURL: https://notify.paweltanski.com`

After a `puls-dnia-news` publish, verify:

- GitHub webhook delivery returns `200`;
- `/status.lastWebhook.status` is `processed`;
- `/status.lastApnsDelivery.sent >= 1`;
- iPhone receives `Puls Dnia - nowych: N`.
