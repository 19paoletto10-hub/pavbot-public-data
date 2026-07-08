# Legacy Live iOS Notifications With Contabo/VPS

Pavbot legacy APNs notifier utilities can run on Contabo as an optional
production host. Current briefing notifications do not use this path; the iOS
app receives briefing pushes from the CloudKit `Briefing` subscription.

This repository keeps the MacBook setup as a development/backup path. The
Contabo path is isolated so it can share a server with other applications.

## Production Endpoint

Recommended public URL:

```text
https://notifier.example.com
```

The service itself must stay private on localhost:

```text
127.0.0.1:18082 -> pavbot-notifier:8080
```

Do not expose container port `8080` directly to the internet. GitHub, iOS, and
APNs-facing diagnostics should only use HTTPS on your notifier domain.

## Architecture

- Codex automations publish artifacts and `public/pavbot-manifest.json` to
  `origin/main`.
- GitHub sends one `push` webhook to
  `https://notifier.example.com/webhooks/github`.
- The Contabo notifier fetches `PAVBOT_MANIFEST_URL`, diffs the manifest, and
  sends APNs alerts for new artifacts.
- Legacy iOS builds can register device tokens with
  `POST https://notifier.example.com/v1/devices`.
- The app can restore connection defaults from
  `GET https://notifier.example.com/v1/app/defaults`.

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
  your notifier domain.
- `backend/pavbot-notifier/nginx/pavbot-notifier.example.conf` - Nginx vhost
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
PAVBOT_PUBLIC_NOTIFIER_URL=https://notifier.example.com
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

Use `APNS_ENV=production` for current Pavbot builds; the app target signs with
the production APNs environment.

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
cp /opt/pavbot-notifier/nginx/pavbot-notifier.example.conf \
  /etc/nginx/sites-available/pavbot-notifier.conf
ln -sfn /etc/nginx/sites-available/pavbot-notifier.conf \
  /etc/nginx/sites-enabled/pavbot-notifier.conf
```

Create the certificate:

```bash
certbot certonly --webroot \
  -w /var/www/paweltanski/webroot \
  -d notifier.example.com
```

Then validate and reload:

```bash
nginx -t
systemctl reload nginx
```

## GitHub And iOS Cutover

GitHub webhook:

```text
Payload URL: https://notifier.example.com/webhooks/github
Content type: application/json
Secret: same as GITHUB_WEBHOOK_SECRET
Events: push
```

iOS briefing push is configured in-app through CloudKit under
`Ustawienia -> Powiadomienia -> Tryb briefingów`. Legacy builds that still use a
notifier URL should point at the generic notifier domain above.

## Verification

On the server:

```bash
curl http://127.0.0.1:18082/healthz
curl http://127.0.0.1:18082/status
```

Publicly:

```bash
curl https://notifier.example.com/healthz
curl https://notifier.example.com/status
curl https://notifier.example.com/v1/app/defaults
```

Expected `/status` after iOS registration:

- `apnsConfigured: true`
- `apnsEnvironment: production`
- `registeredDevices >= 1`
- `publicNotifierURL: https://notifier.example.com`

After a `puls-dnia-news` publish, verify:

- GitHub webhook delivery returns `200`;
- `/status.lastWebhook.status` is `processed`;
- `/status.lastApnsDelivery.sent >= 1`;
- iPhone receives `Puls Dnia - nowych: N`.
