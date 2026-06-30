#!/usr/bin/env bash
set -euo pipefail

SSH_HOST="${PAVBOT_CONTABO_SSH_HOST:-contabo}"
REMOTE_DIR="${PAVBOT_CONTABO_REMOTE_DIR:-/opt/pavbot-notifier}"
BIND_PORT="${PAVBOT_CONTABO_BIND_PORT:-18082}"
MIN_FREE_MB="${PAVBOT_CONTABO_MIN_FREE_MB:-4096}"
COMPOSE_PROJECT="${PAVBOT_CONTABO_COMPOSE_PROJECT:-pavbot-notifier}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVICE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

usage() {
  cat <<EOF
Usage: $0 [--start]

Copies backend/pavbot-notifier to Contabo without overwriting .env or secrets.

Environment:
  PAVBOT_CONTABO_SSH_HOST        SSH host alias, default: contabo
  PAVBOT_CONTABO_REMOTE_DIR      Remote directory, default: /opt/pavbot-notifier
  PAVBOT_CONTABO_BIND_PORT       Local proxy port, default: 18082
  PAVBOT_CONTABO_MIN_FREE_MB     Minimum free disk MB checked remotely, default: 4096

Options:
  --start                        Run docker compose up -d --build after copy
EOF
}

START=0
case "${1:-}" in
  --start) START=1 ;;
  -h|--help) usage; exit 0 ;;
  "") ;;
  *) usage >&2; exit 2 ;;
esac

echo "Deploying Pavbot notifier code to ${SSH_HOST}:${REMOTE_DIR}"

ssh "$SSH_HOST" "BIND_PORT='$BIND_PORT' MIN_FREE_MB='$MIN_FREE_MB' REMOTE_DIR='$REMOTE_DIR' COMPOSE_PROJECT='$COMPOSE_PROJECT' bash -s" <<'REMOTE_PREFLIGHT'
set -euo pipefail
free_mb="$(df -Pm / | awk 'NR == 2 {print $4}')"
echo "remoteAvailableMB=$free_mb"
if (( free_mb < MIN_FREE_MB )); then
  echo "ERROR: only ${free_mb}MB free on /. Required at least ${MIN_FREE_MB}MB." >&2
  echo "Review Docker build cache/images before deploying Pavbot notifier." >&2
  exit 20
fi
if command -v ss >/dev/null 2>&1; then
  if ss -ltn | awk '{print $4}' | grep -Eq "(:|\.)${BIND_PORT}$"; then
    if (
      cd "$REMOTE_DIR" 2>/dev/null &&
        PAVBOT_CONTABO_BIND_PORT="$BIND_PORT" \
          docker compose -p "$COMPOSE_PROJECT" -f docker-compose.yml -f docker-compose.contabo.yml \
          ps --services --filter status=running 2>/dev/null |
          grep -qx 'pavbot-notifier'
    ); then
      echo "remotePortInUse=existing pavbot-notifier service; redeploy allowed"
    else
      echo "ERROR: 127.0.0.1:${BIND_PORT} is already in use by another service." >&2
      exit 21
    fi
  fi
fi
command -v docker >/dev/null
docker compose version >/dev/null
REMOTE_PREFLIGHT

ssh "$SSH_HOST" "mkdir -p '$REMOTE_DIR' '$REMOTE_DIR/secrets'"

rsync -az --delete \
  --exclude '.env' \
  --exclude 'secrets/' \
  --exclude '__pycache__/' \
  --exclude '.pytest_cache/' \
  --exclude '*.pyc' \
  "$SERVICE_DIR/" "$SSH_HOST:$REMOTE_DIR/"

ssh "$SSH_HOST" "cd '$REMOTE_DIR' && chmod +x scripts/contabo-preflight.sh scripts/deploy-contabo.sh && PAVBOT_CONTABO_BIND_PORT='$BIND_PORT' PAVBOT_CONTABO_COMPOSE_PROJECT='$COMPOSE_PROJECT' scripts/contabo-preflight.sh"

ssh "$SSH_HOST" "cd '$REMOTE_DIR' && if [ ! -f .env ]; then cp .env.contabo.example .env; chmod 600 .env; echo 'Created .env from .env.contabo.example; fill secrets before starting.'; fi"

ssh "$SSH_HOST" "cd '$REMOTE_DIR' && PAVBOT_CONTABO_BIND_PORT='$BIND_PORT' docker compose -p '$COMPOSE_PROJECT' -f docker-compose.yml -f docker-compose.contabo.yml config >/dev/null"

if (( START == 1 )); then
  ssh "$SSH_HOST" "cd '$REMOTE_DIR' && PAVBOT_CONTABO_BIND_PORT='$BIND_PORT' docker compose -p '$COMPOSE_PROJECT' -f docker-compose.yml -f docker-compose.contabo.yml up -d --build"
  ssh "$SSH_HOST" "curl -fsS http://127.0.0.1:${BIND_PORT}/healthz && echo && curl -fsS http://127.0.0.1:${BIND_PORT}/status"
else
  echo "Code copied and compose validated. Fill ${REMOTE_DIR}/.env and secrets, then rerun with --start."
fi
