---
name: pavbot-live-notifier
description: Use when Codex is asked to set up, debug, verify, or operate Pavbot iOS live notifications, GitHub webhook delivery, APNs device registration, Docker notifier hosting, or Cloudflare Tunnel on a MacBook.
---

# Pavbot Live Notifier

Operate the optional iOS live notification add-on for Pavbot.

## Read First

1. `AGENTS.md`
2. `docs/live-ios-notifications-macbook-cloudflare.md`
3. `backend/pavbot-notifier/README.md`
4. `backend/pavbot-notifier/.env.example`

Use `docs/live-ios-notifications-contabo.md` only when the user explicitly asks
for the VPS/Contabo path.

## Workflow

1. Confirm the active manifest URL is the same value in:
   - iOS `Settings -> Manifest URL`
   - notifier `.env` as `PAVBOT_MANIFEST_URL`
   - Codex automation environment as `PAVBOT_MANIFEST_URL`
2. Confirm each active automation finishes by running
   `scripts/pavbot_commit_and_push_outputs.sh research/<topic>`. The GitHub
   webhook only fires after the automation pushes its topic artifacts and
   refreshed `public/pavbot-manifest.json` to `origin/main`.
3. Check local notifier health:
   ```bash
   cd backend/pavbot-notifier
   docker compose ps
   curl http://localhost:8080/healthz
   curl http://localhost:8080/status
   ```
4. Check public Cloudflare Tunnel health:
   ```bash
   curl https://<cloudflare-domain>/healthz
   curl https://<cloudflare-domain>/status
   ```
5. Check GitHub webhook delivery in repository settings. The payload URL must
   be `https://<cloudflare-domain>/webhooks/github`, event `push`, content type
   `application/json`, and secret matching `GITHUB_WEBHOOK_SECRET`.
6. If iOS has no push alerts, verify `/status` shows `registeredDevices > 0`,
   a recent `lastWebhook`, `apnsConfigured: true`, and the expected
   `manifestURL`.

## Safety Rules

- Never commit `.env`, APNs `.p8` keys, tokens, or Cloudflare credentials.
- Do not add Push Notifications entitlement to the default `PavbotViewer`
  scheme. Use the push-enabled variant only when Apple Developer setup is done.
- If Apple signing fails with PLA or missing Push Notifications capability,
  report the exact Apple-side action instead of trying to bypass signing.
- The MacBook must be awake and online. Codex can create/run scripts, but the
  Docker container and `cloudflared` process are the actual host.

## Verification

Run:

```bash
scripts/verify-research-workspace.sh
.venv/bin/python -m pytest -q
docker compose -f backend/pavbot-notifier/docker-compose.yml build
```

For iOS changes, also run the simulator test suite through XcodeBuildMCP.
