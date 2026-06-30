#!/usr/bin/env bash
set -euo pipefail

BIND_PORT="${PAVBOT_CONTABO_BIND_PORT:-18082}"
MIN_FREE_MB="${PAVBOT_CONTABO_MIN_FREE_MB:-4096}"
TARGET_DIR="${PAVBOT_CONTABO_REMOTE_DIR:-/opt/pavbot-notifier}"
COMPOSE_PROJECT="${PAVBOT_CONTABO_COMPOSE_PROJECT:-pavbot-notifier}"

available_mb() {
  df -Pm / | awk 'NR == 2 {print $4}'
}

port_is_free() {
  local port="$1"
  if command -v ss >/dev/null 2>&1; then
    ! ss -ltn | awk '{print $4}' | grep -Eq "(:|\\.)${port}$"
  elif command -v netstat >/dev/null 2>&1; then
    ! netstat -ltn | awk '{print $4}' | grep -Eq "(:|\\.)${port}$"
  else
    return 0
  fi
}

port_is_existing_pavbot_service() {
  local port="$1"
  (
    cd "$TARGET_DIR" 2>/dev/null &&
      PAVBOT_CONTABO_BIND_PORT="$port" \
        docker compose -p "$COMPOSE_PROJECT" -f docker-compose.yml -f docker-compose.contabo.yml \
        ps --services --filter status=running 2>/dev/null |
        grep -qx 'pavbot-notifier'
  )
}

echo "Pavbot notifier Contabo preflight"
echo "targetDir=$TARGET_DIR"
echo "bindPort=$BIND_PORT"
echo

echo "--- disk ---"
df -h /
free_mb="$(available_mb)"
echo "availableMB=$free_mb"
if (( free_mb < MIN_FREE_MB )); then
  echo "ERROR: only ${free_mb}MB free on /. Required at least ${MIN_FREE_MB}MB." >&2
  echo "Do not build new Docker images until old build cache/images are reviewed." >&2
  exit 20
fi

echo
echo "--- docker ---"
command -v docker >/dev/null
docker --version
docker compose version
docker system df || true

echo
echo "--- port ---"
if ! port_is_free "$BIND_PORT"; then
  if port_is_existing_pavbot_service "$BIND_PORT"; then
    echo "port ${BIND_PORT} is already used by the existing pavbot-notifier service; redeploy allowed"
  else
    echo "ERROR: 127.0.0.1:${BIND_PORT} is already in use by another service. Set PAVBOT_CONTABO_BIND_PORT to a free local port." >&2
    exit 21
  fi
else
  echo "port ${BIND_PORT} is free"
fi

echo
echo "--- nginx ---"
if command -v nginx >/dev/null 2>&1; then
  nginx -t
else
  echo "nginx not found; configure an existing reverse proxy before exposing notify.paweltanski.com"
fi

echo
echo "preflight ok"
