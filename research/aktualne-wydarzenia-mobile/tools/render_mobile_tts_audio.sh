#!/usr/bin/env bash
set -u -o pipefail

if [[ $# -ne 2 ]]; then
  printf 'usage: %s SCRIPT_MD PODCAST_DIR\n' "$0" >&2
  exit 64
fi

script_file=$1
podcast_dir=$2
variant_id="female-piper"
engine="piper"
voice="pl_PL-gosia-medium"
model_label="rhasspy/piper-voices:pl_PL-gosia-medium"
speed=${PAVBOT_TTS_SPEED_MULTIPLIER:-1.03}
python_bin=${PAVBOT_PYTHON:-python3}
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../../.." && pwd)"
shared_renderer=${PAVBOT_SHARED_RENDERER:-"$repo_root/.agents/scripts/podcast/render-podcast-audio.sh"}
variant_dir="$podcast_dir/audio/$variant_id"
raw_mp3="$variant_dir/podcast.raw.mp3"
final_mp3="$variant_dir/podcast.mp3"
log_file="$variant_dir/render.log"
render_json="$variant_dir/render.json"
summary_json="$podcast_dir/tts_variants.json"

mkdir -p "$variant_dir"

fail() {
  local message=$1
  printf '%s\n' "$message" >&2
  write_failed_json "$message"
  write_summary_json
  exit 70
}

write_failed_json() {
  local message=$1
  "$python_bin" - "$render_json" "$variant_id" "$engine" "$voice" "$language" "$speed" "$message" <<'PY'
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

path, variant_id, engine, voice, language, speed, message = sys.argv[1:]
payload = {
    "created_at": datetime.now(timezone.utc).isoformat(),
    "variant_id": variant_id,
    "engine_requested": engine,
    "engine_used": None,
    "voice": voice,
    "language": language,
    "speed": float(speed),
    "status": "failed",
    "error": message.strip() or "render failed",
    "output_file": None,
}
Path(path).write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
}

write_success_json() {
  local final_duration=$1
  "$python_bin" - "$render_json" "$variant_id" "$engine" "$voice" "$language" "$speed" "$final_mp3" "$model_label" "$final_duration" <<'PY'
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

path, variant_id, engine, voice, language, speed, final_mp3, model_label, final_duration = sys.argv[1:]
render_path = Path(path)
existing = {}
if render_path.is_file():
    existing = json.loads(render_path.read_text(encoding="utf-8"))
raw_duration = existing.get("duration_seconds")
existing.update(
    {
        "created_at": existing.get("created_at") or datetime.now(timezone.utc).isoformat(),
        "variant_id": variant_id,
        "engine_requested": engine,
        "engine_used": existing.get("engine_used") or engine,
        "model": existing.get("model") or model_label,
        "voice": voice,
        "language": language,
        "speed": float(speed),
        "speed_filter": f"atempo={speed}",
        "original_duration_seconds": raw_duration,
        "duration_seconds": float(final_duration),
        "status": "ok",
        "raw_output_file": None,
        "output_file": final_mp3,
        "error": None,
    }
)
render_path.write_text(json.dumps(existing, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
}

write_summary_json() {
  "$python_bin" - "$summary_json" "$language" "$speed" "$render_json" <<'PY'
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

output = Path(sys.argv[1])
language = sys.argv[2]
speed = float(sys.argv[3])
render_path = Path(sys.argv[4])
payload = json.loads(render_path.read_text(encoding="utf-8"))
variant = {
    "id": payload.get("variant_id"),
    "engine": payload.get("engine_used") or payload.get("engine_requested"),
    "voice": payload.get("voice"),
    "model": payload.get("model"),
    "status": payload.get("status"),
    "duration_seconds": payload.get("duration_seconds"),
    "output_file": payload.get("output_file"),
    "render_json": str(render_path),
    "error": payload.get("error"),
}
summary = {
    "created_at": datetime.now(timezone.utc).isoformat(),
    "language": language,
    "language_detection": "local-polish-heuristic",
    "speed": speed,
    "variants": [variant],
}
output.write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
}

detect_language() {
  "$python_bin" - "$script_file" <<'PY'
import re
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text(encoding="utf-8", errors="ignore").lower()
polish_score = len(re.findall(r"[ąćęłńóśźż]", text))
common_score = len(re.findall(r"\b(że|jest|oraz|dla|polska|dzisiaj|rząd|świat|wydarzeń)\b", text))
print("pl" if polish_score or common_score else "pl")
PY
}

language="pl"

if [[ ! -f "$script_file" ]]; then
  fail "script file not found: $script_file"
fi

if [[ ! -f "$shared_renderer" ]]; then
  fail "shared renderer not found: $shared_renderer"
fi

for required in ffmpeg ffprobe; do
  if ! command -v "$required" >/dev/null 2>&1; then
    fail "required command not found: $required"
  fi
done

language="$(detect_language)"
rm -f "$raw_mp3" "$final_mp3" "$log_file"

if ! PAVBOT_TTS_ENGINE="$engine" bash "$shared_renderer" "$script_file" "$raw_mp3" "$voice" >"$log_file" 2>&1; then
  fail "$(cat "$log_file" 2>/dev/null)"
fi

if [[ ! -s "$raw_mp3" ]]; then
  fail "required TTS renderer did not create audio: $raw_mp3"
fi

if ! ffmpeg -hide_banner -loglevel error -y -i "$raw_mp3" -filter:a "atempo=$speed" -codec:a libmp3lame -q:a 4 "$final_mp3" >>"$log_file" 2>&1; then
  fail "$(cat "$log_file" 2>/dev/null)"
fi

if [[ ! -s "$final_mp3" ]]; then
  fail "required TTS renderer did not create final audio: $final_mp3"
fi

final_duration="$(ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$final_mp3" 2>>"$log_file")"
if [[ -z "$final_duration" ]]; then
  fail "ffprobe did not return a duration for $final_mp3"
fi

write_success_json "$final_duration"
write_summary_json
rm -f "$raw_mp3" "$log_file"
printf 'created required TTS variant in %s\n' "$variant_dir"
