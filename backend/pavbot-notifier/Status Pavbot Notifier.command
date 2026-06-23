#!/usr/bin/env bash
set -euo pipefail

SERVICE_DIR="$(cd "$(dirname "$0")" && pwd -P)"
cd "$SERVICE_DIR"

echo "== Pavbot Notifier Status =="
docker compose ps || true

echo
echo "Local health:"
curl -fsS http://localhost:8080/healthz || true

echo
echo "Local status:"
curl -fsS http://localhost:8080/status || true
echo

if [[ -f .env ]]; then
  public_url="$(awk -F= '/^PAVBOT_PUBLIC_NOTIFIER_URL=/{print $2}' .env | tr -d '[:space:]' | sed 's:/*$::')"
  if [[ -n "$public_url" && "$public_url" != "https://notify.example.com" ]]; then
    echo
    echo "Public status:"
    curl -fsS "$public_url/status" || true
    open "$public_url/status" >/dev/null 2>&1 || true
  else
    open "http://localhost:8080/status" >/dev/null 2>&1 || true
  fi
else
  echo ".env does not exist yet. Double-click Start Pavbot Notifier.command first."
fi
