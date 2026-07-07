#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVICE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_DIR="$(cd "$SERVICE_DIR/../.." && pwd)"
LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"

mkdir -p "$LAUNCH_AGENTS_DIR"

notifier_plist="$LAUNCH_AGENTS_DIR/com.pavbot.notifier.plist"
cloudflared_plist="$LAUNCH_AGENTS_DIR/com.pavbot.cloudflared.plist"

sed "s#/Users/YOU/Documents/CODEX-Pavbot#$REPO_DIR#g" \
  "$SERVICE_DIR/launchd/com.pavbot.notifier.plist.example" >"$notifier_plist"

if [[ -f "$HOME/.cloudflared/pavbot-notifier.yml" ]]; then
  sed "s#/Users/YOU#$HOME#g" \
    "$SERVICE_DIR/launchd/com.pavbot.cloudflared.plist.example" >"$cloudflared_plist"
else
  echo "Skipping cloudflared LaunchAgent because $HOME/.cloudflared/pavbot-notifier.yml does not exist yet."
  echo "Create it from backend/pavbot-notifier/cloudflare/config.example.yml, then rerun this script."
fi

launchctl unload "$notifier_plist" >/dev/null 2>&1 || true
launchctl load "$notifier_plist"

if [[ -f "$cloudflared_plist" ]]; then
  launchctl unload "$cloudflared_plist" >/dev/null 2>&1 || true
  launchctl load "$cloudflared_plist"
fi

echo "Installed Pavbot notifier LaunchAgents in $LAUNCH_AGENTS_DIR."
