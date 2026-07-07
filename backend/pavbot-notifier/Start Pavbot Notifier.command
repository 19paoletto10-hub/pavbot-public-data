#!/usr/bin/env bash
set -euo pipefail

SERVICE_DIR="$(cd "$(dirname "$0")" && pwd -P)"
cd "$SERVICE_DIR"

echo "== Pavbot Notifier =="
echo "Service: $SERVICE_DIR"

if ! command -v docker >/dev/null 2>&1; then
  echo "Docker is not installed or not on PATH."
  echo "Install Docker Desktop, then run this file again."
  open -a Docker >/dev/null 2>&1 || true
  exit 1
fi

if ! docker info >/dev/null 2>&1; then
  echo "Docker is not running. Opening Docker Desktop..."
  open -a Docker >/dev/null 2>&1 || true
  echo "Wait until Docker Desktop is ready, then run this file again."
  exit 1
fi

if [[ ! -f .env ]]; then
  cp .env.example .env
  mkdir -p secrets
  echo "Created .env from .env.example."
  echo "Fill APNS_KEY_ID, GITHUB_WEBHOOK_SECRET, PAVBOT_PUBLIC_NOTIFIER_URL and place AuthKey_<APNS_KEY_ID>.p8 in:"
  echo "$SERVICE_DIR/secrets"
  open -e .env >/dev/null 2>&1 || true
  open "$SERVICE_DIR/secrets" >/dev/null 2>&1 || true
  exit 1
fi

mkdir -p secrets
echo "Starting Docker notifier..."
docker compose up -d --build

echo
echo "Local health:"
curl -fsS http://localhost:8080/healthz || true
echo
echo "Local status:"
curl -fsS http://localhost:8080/status || true
echo

if [[ -f "$HOME/.cloudflared/pavbot-notifier.yml" ]]; then
  if command -v cloudflared >/dev/null 2>&1; then
    if pgrep -f "cloudflared.*pavbot-notifier" >/dev/null 2>&1; then
      echo "Cloudflare tunnel already appears to be running."
    else
      echo "Starting Cloudflare tunnel in the background..."
      nohup cloudflared tunnel --config "$HOME/.cloudflared/pavbot-notifier.yml" run pavbot-notifier \
        >/tmp/com.pavbot.cloudflared.out.log \
        2>/tmp/com.pavbot.cloudflared.err.log &
    fi
  else
    echo "cloudflared is not installed. Install with: brew install cloudflared"
  fi
else
  echo "Cloudflare config not found at ~/.cloudflared/pavbot-notifier.yml."
  echo "Local notifier is running, but GitHub/iPhone live webhooks need the public tunnel."
fi

public_url="$(awk -F= '/^PAVBOT_PUBLIC_NOTIFIER_URL=/{print $2}' .env | tr -d '[:space:]' | sed 's:/*$::')"
if [[ -n "$public_url" && "$public_url" != "https://notify.example.com" ]]; then
  echo
  echo "Public status:"
  curl -fsS "$public_url/status" || true
  open "$public_url/status" >/dev/null 2>&1 || true
else
  open "http://localhost:8080/status" >/dev/null 2>&1 || true
fi

echo
echo "Done. Keep this MacBook awake for live notifications."
