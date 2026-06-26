#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 2 || $# -gt 4 ]]; then
  printf 'usage: %s SCRIPT_MD OUTPUT_MP3 [VOICE] [RATE]\n' "$0" >&2
  exit 64
fi

script_file=$1
output_mp3=$2
voice=${3:-${PAVBOT_TTS_VOICE:-Zosia}}
rate=${4:-${PAVBOT_TTS_RATE:-170}}
engine_requested=${PAVBOT_TTS_ENGINE:-auto}
model_dir=${PAVBOT_TTS_MODEL_DIR:-"$HOME/.cache/pavbot/tts-models"}
voice_sample=${PAVBOT_TTS_VOICE_SAMPLE:-}
xtts_timeout_seconds=${PAVBOT_TTS_XTTS_TIMEOUT_SECONDS:-}

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

if [[ ! -f "$script_file" ]]; then
  printf 'script file not found: %s\n' "$script_file" >&2
  exit 66
fi

mkdir -p "$(dirname "$output_mp3")"
tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

spoken_text="$tmp_dir/spoken.txt"
audio_aiff="$tmp_dir/podcast.aiff"
audio_wav="$tmp_dir/podcast.wav"
render_json="$(dirname "$output_mp3")/render.json"

sed \
  -e 's/\r$//' \
  -e '/^#/d' \
  -e '/^```/d' \
  -e 's/\[[^]]*\](https\?:\/\/[^)]*)//g' \
  -e 's/https\?:\/\/[^[:space:])]*//g' \
  -e 's/[*_`>]//g' \
  "$script_file" \
  | awk 'NF { print }' > "$spoken_text"

if [[ ! -s "$spoken_text" ]]; then
  printf 'script contains no speakable text after Markdown cleanup\n' >&2
  exit 65
fi

word_count=$(awk 'BEGIN { count = 0 } { count += NF } END { print count }' "$spoken_text")

duration_seconds() {
  ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$output_mp3"
}

write_render_json() {
  local engine_used=$1
  local model_used=$2
  local fallback_chain=$3
  local duration=$4

  python3 - "$render_json" "$engine_requested" "$engine_used" "$model_used" "$fallback_chain" "$duration" "$word_count" "$voice" "$rate" "$voice_sample" <<'PY'
import json
import sys
from datetime import datetime, timezone

path, requested, used, model, chain, duration, words, voice, rate, sample = sys.argv[1:]
payload = {
    "created_at": datetime.now(timezone.utc).isoformat(),
    "engine_requested": requested,
    "engine_used": used,
    "model": model,
    "fallback_chain": [item for item in chain.split(",") if item],
    "duration_seconds": float(duration),
    "word_count": int(words),
    "voice": voice,
    "rate": int(rate),
    "voice_sample_path": sample or None,
}
with open(path, "w", encoding="utf-8") as f:
    json.dump(payload, f, ensure_ascii=False, indent=2)
    f.write("\n")
PY
}

finish_render() {
  local engine_used=$1
  local model_used=$2
  local fallback_chain=$3

  if [[ ! -s "$output_mp3" ]]; then
    printf 'MP3 output was not created: %s\n' "$output_mp3" >&2
    return 70
  fi

  local duration
  duration=$(duration_seconds)
  write_render_json "$engine_used" "$model_used" "$fallback_chain" "$duration"
  printf 'created %s with %s (%ss)\n' "$output_mp3" "$engine_used" "$duration"
}

try_say() {
  command -v say >/dev/null 2>&1 || return 69
  command -v ffmpeg >/dev/null 2>&1 || return 69
  say -v '?' | awk '{print $1}' | grep -Fxq "$voice" || return 69
  say -v "$voice" -r "$rate" -f "$spoken_text" -o "$audio_aiff" || return 69
  ffmpeg -hide_banner -loglevel error -y -i "$audio_aiff" -codec:a libmp3lame -q:a 4 "$output_mp3" || return 69
}

find_piper_bin() {
  if [[ -n "${PAVBOT_PIPER_BIN:-}" && -x "${PAVBOT_PIPER_BIN:-}" ]]; then
    printf '%s\n' "$PAVBOT_PIPER_BIN"
    return 0
  fi
  if [[ -x "$HOME/.cache/pavbot/venvs/piper/bin/piper" ]]; then
    printf '%s\n' "$HOME/.cache/pavbot/venvs/piper/bin/piper"
    return 0
  fi
  command -v piper 2>/dev/null || return 69
}

try_piper() {
  command -v ffmpeg >/dev/null 2>&1 || return 69
  local piper_bin
  piper_bin=$(find_piper_bin) || return 69
  local model="$model_dir/piper-voices/pl/pl_PL/gosia/medium/pl_PL-gosia-medium.onnx"
  [[ -f "$model" ]] || return 69
  "$piper_bin" --model "$model" --output_file "$audio_wav" < "$spoken_text" || return 69
  ffmpeg -hide_banner -loglevel error -y -i "$audio_wav" -codec:a libmp3lame -q:a 4 "$output_mp3" || return 69
}

run_with_timeout() {
  local seconds=$1
  shift

  if command -v timeout >/dev/null 2>&1; then
    timeout "$seconds" "$@"
    return $?
  fi

  python3 - "$seconds" "$@" <<'PY'
import subprocess
import sys

timeout_seconds = int(sys.argv[1])
cmd = sys.argv[2:]

try:
    completed = subprocess.run(cmd, check=False, timeout=timeout_seconds)
except subprocess.TimeoutExpired:
    print(f"xtts render exceeded timeout of {timeout_seconds}s")
    raise SystemExit(124)

raise SystemExit(completed.returncode)
PY
}

try_xtts() {
  command -v ffmpeg >/dev/null 2>&1 || return 69
  local xtts_python=${PAVBOT_XTTS_PYTHON:-"$HOME/.cache/pavbot/venvs/xtts/bin/python"}
  [[ -x "$xtts_python" ]] || return 69
  local render_cmd=( "$xtts_python" "$script_dir/render_xtts.py" "$spoken_text" "$audio_wav" "$model_dir/xtts-v2" )
  if [[ -n "$xtts_timeout_seconds" ]]; then
    if ! [[ "$xtts_timeout_seconds" =~ ^[0-9]+$ ]]; then
      return 67
    fi
    if ! run_with_timeout "$xtts_timeout_seconds" "${render_cmd[@]}"; then
      return 69
    fi
  else
    "${render_cmd[@]}" || return 69
  fi
  ffmpeg -hide_banner -loglevel error -y -i "$audio_wav" -codec:a libmp3lame -q:a 4 "$output_mp3" || return 69
}

attempt_engine() {
  local engine=$1
  set +e
  "try_$engine"
  local rc=$?
  set -e
  return "$rc"
}

fallback_chain=()

case "$engine_requested" in
  say)
    attempt_engine say
    finish_render "say" "macOS say:$voice" ""
    ;;
  piper)
    attempt_engine piper
    finish_render "piper" "rhasspy/piper-voices:pl_PL-gosia-medium" ""
    ;;
  xtts)
    attempt_engine xtts
    finish_render "xtts" "coqui/XTTS-v2" ""
    ;;
  auto)
    if attempt_engine xtts; then
      finish_render "xtts" "coqui/XTTS-v2" ""
    else
      fallback_chain+=("xtts_failed")
      if attempt_engine piper; then
        finish_render "piper" "rhasspy/piper-voices:pl_PL-gosia-medium" "$(IFS=,; printf '%s' "${fallback_chain[*]}")"
      else
        fallback_chain+=("piper_failed")
        attempt_engine say
        finish_render "say" "macOS say:$voice" "$(IFS=,; printf '%s' "${fallback_chain[*]}")"
      fi
    fi
    ;;
  *)
    printf 'unknown PAVBOT_TTS_ENGINE: %s\n' "$engine_requested" >&2
    exit 64
    ;;
esac
