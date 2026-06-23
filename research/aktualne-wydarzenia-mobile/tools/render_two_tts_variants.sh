#!/usr/bin/env bash
set -u -o pipefail

if [[ $# -ne 2 ]]; then
  printf 'usage: %s SCRIPT_MD PODCAST_DIR\n' "$0" >&2
  exit 64
fi

script_file=$1
podcast_dir=$2
speed=${PAVBOT_TTS_SPEED_MULTIPLIER:-1.1}
python_bin=${PAVBOT_PYTHON:-python3}
shared_renderer=".agents/scripts/podcast/render-podcast-audio.sh"

if [[ ! -f "$script_file" ]]; then
  printf 'script file not found: %s\n' "$script_file" >&2
  exit 66
fi

if [[ ! -x "$shared_renderer" && ! -f "$shared_renderer" ]]; then
  printf 'shared renderer not found: %s\n' "$shared_renderer" >&2
  exit 66
fi

mkdir -p "$podcast_dir/audio"
language=$("$python_bin" - "$script_file" <<'PY'
import re
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text(encoding="utf-8", errors="ignore").lower()
polish_score = len(re.findall(r"[ąćęłńóśźż]", text))
common_score = len(re.findall(r"\b(że|jest|oraz|dla|polska|dzisiaj|rząd|świat|wydarzeń)\b", text))
print("pl" if polish_score or common_score else "pl")
PY
)

render_status=()
variant_json_files=()

json_escape() {
  "$python_bin" -c 'import json,sys; print(json.dumps(sys.stdin.read()))'
}

write_failed_json() {
  local variant_id=$1
  local engine=$2
  local voice=$3
  local variant_dir=$4
  local message=$5
  "$python_bin" - "$variant_dir/render.json" "$variant_id" "$engine" "$voice" "$language" "$speed" "$message" <<'PY'
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
  local variant_id=$1
  local engine=$2
  local voice=$3
  local variant_dir=$4
  local raw_mp3=$5
  local final_mp3=$6
  local model_label=$7
  local final_duration=$8
  "$python_bin" - "$variant_dir/render.json" "$variant_id" "$engine" "$voice" "$language" "$speed" "$raw_mp3" "$final_mp3" "$model_label" "$final_duration" <<'PY'
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

path, variant_id, engine, voice, language, speed, raw_mp3, final_mp3, model_label, final_duration = sys.argv[1:]
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
    }
)
render_path.write_text(json.dumps(existing, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
}

render_variant() {
  local variant_id=$1
  local engine=$2
  local voice=$3
  local speaker=$4
  local model_label=$5
  local variant_dir="$podcast_dir/audio/$variant_id"
  local raw_mp3="$variant_dir/podcast.raw.mp3"
  local final_mp3="$variant_dir/podcast.mp3"
  local log_file="$variant_dir/render.log"
  mkdir -p "$variant_dir"
  rm -f "$raw_mp3" "$final_mp3" "$log_file"

  set +e
  if [[ "$engine" == "xtts" ]]; then
    PAVBOT_TTS_ENGINE=xtts \
      PAVBOT_XTTS_SPEAKER="$speaker" \
      PAVBOT_XTTS_LANGUAGE="$language" \
      bash "$shared_renderer" "$script_file" "$raw_mp3" "$voice" >"$log_file" 2>&1
  else
    PAVBOT_TTS_ENGINE="$engine" \
      bash "$shared_renderer" "$script_file" "$raw_mp3" "$voice" >"$log_file" 2>&1
  fi
  local render_rc=$?
  set -e

  if [[ $render_rc -ne 0 || ! -s "$raw_mp3" ]]; then
    write_failed_json "$variant_id" "$engine" "$voice" "$variant_dir" "$(cat "$log_file" 2>/dev/null)"
    render_status+=("$variant_id:failed")
    variant_json_files+=("$variant_dir/render.json")
    return 0
  fi

  set +e
  ffmpeg -hide_banner -loglevel error -y -i "$raw_mp3" -filter:a "atempo=$speed" -codec:a libmp3lame -q:a 4 "$final_mp3" >>"$log_file" 2>&1
  local speed_rc=$?
  set -e

  if [[ $speed_rc -ne 0 || ! -s "$final_mp3" ]]; then
    write_failed_json "$variant_id" "$engine" "$voice" "$variant_dir" "$(cat "$log_file" 2>/dev/null)"
    render_status+=("$variant_id:failed")
    variant_json_files+=("$variant_dir/render.json")
    return 0
  fi

  local final_duration
  final_duration=$(ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$final_mp3" 2>>"$log_file")
  write_success_json "$variant_id" "$engine" "$voice" "$variant_dir" "$raw_mp3" "$final_mp3" "$model_label" "$final_duration"
  rm -f "$raw_mp3" "$log_file"
  render_status+=("$variant_id:ok")
  variant_json_files+=("$variant_dir/render.json")
}

set -e
render_variant "female-piper" "piper" "pl_PL-gosia-medium" "" "rhasspy/piper-voices:pl_PL-gosia-medium"
render_variant "male-xtts" "xtts" "Andrew Chipper" "Andrew Chipper" "coqui/XTTS-v2"

"$python_bin" - "$podcast_dir/tts_variants.json" "$language" "$speed" "${variant_json_files[@]}" <<'PY'
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

output = Path(sys.argv[1])
language = sys.argv[2]
speed = float(sys.argv[3])
variants = []
for path_value in sys.argv[4:]:
    path = Path(path_value)
    payload = json.loads(path.read_text(encoding="utf-8"))
    variants.append(
        {
            "id": payload.get("variant_id"),
            "engine": payload.get("engine_used") or payload.get("engine_requested"),
            "voice": payload.get("voice"),
            "model": payload.get("model"),
            "status": payload.get("status"),
            "duration_seconds": payload.get("duration_seconds"),
            "output_file": payload.get("output_file"),
            "render_json": str(path),
            "error": payload.get("error"),
        }
    )

payload = {
    "created_at": datetime.now(timezone.utc).isoformat(),
    "language": language,
    "language_detection": "local-polish-heuristic",
    "speed": speed,
    "variants": variants,
}
output.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY

failed=0
for item in "${render_status[@]}"; do
  if [[ "$item" == *":failed" ]]; then
    failed=1
  fi
done

if [[ $failed -ne 0 ]]; then
  printf 'one or more TTS variants failed; see %s\n' "$podcast_dir/tts_variants.json" >&2
  exit 70
fi

printf 'created TTS variants in %s/audio\n' "$podcast_dir"
