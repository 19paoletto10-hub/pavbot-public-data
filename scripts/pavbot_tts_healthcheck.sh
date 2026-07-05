#!/usr/bin/env bash
set -euo pipefail

output=""
while (($# > 0)); do
  case "$1" in
    --output)
      output="${2:-}"
      shift 2
      ;;
    -h|--help)
      printf 'usage: %s [--output PATH]\n' "$0"
      exit 0
      ;;
    *)
      printf 'unknown argument: %s\n' "$1" >&2
      exit 2
      ;;
  esac
done

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
python_bin="${PAVBOT_PYTHON:-python3}"
shared_renderer="${PAVBOT_SHARED_RENDERER:-"$repo_root/.agents/scripts/podcast/render-podcast-audio.sh"}"
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/pavbot-tts-health.XXXXXX")"
trap 'rm -rf "$tmp_dir"' EXIT

status="ok"
error=""
duration=""
script_file="$tmp_dir/script.md"
mp3_file="$tmp_dir/podcast.mp3"
json_file="${output:-"$tmp_dir/tts-healthcheck.json"}"

mkdir -p "$(dirname "$json_file")"
printf 'To jest krótki test zdrowia lokalnego renderera TTS Pavbot.\n' > "$script_file"

if [[ ! -f "$shared_renderer" ]]; then
  status="failed"
  error="shared renderer not found: $shared_renderer"
elif ! command -v ffprobe >/dev/null 2>&1; then
  status="failed"
  error="required command not found: ffprobe"
elif ! PAVBOT_TTS_ENGINE=piper bash "$shared_renderer" "$script_file" "$mp3_file" "pl_PL-gosia-medium" >/dev/null 2>"$tmp_dir/render.log"; then
  status="failed"
  error="$(cat "$tmp_dir/render.log" 2>/dev/null)"
elif [[ ! -s "$mp3_file" ]]; then
  status="failed"
  error="renderer did not create MP3"
else
  duration="$(ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$mp3_file" 2>/dev/null || true)"
  if [[ -z "$duration" ]]; then
    status="failed"
    error="ffprobe did not return a duration"
  fi
fi

"$python_bin" - "$json_file" "$status" "$error" "$duration" "$shared_renderer" <<'PY'
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

path, status, error, duration, renderer = sys.argv[1:]
payload = {
    "schemaVersion": 1,
    "checkedAt": datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
    "status": status,
    "checks": [
        {
            "id": "shared-piper",
            "engine": "piper",
            "voice": "pl_PL-gosia-medium",
            "renderer": renderer,
            "status": status,
            "durationSeconds": float(duration) if duration else None,
            "error": error or None,
        }
    ],
}
Path(path).write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY

cat "$json_file"
[[ "$status" == "ok" ]]
