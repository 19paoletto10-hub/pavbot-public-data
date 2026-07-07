#!/usr/bin/env bash
set -euo pipefail

model_dir=${PAVBOT_TTS_MODEL_DIR:-"$HOME/.cache/pavbot/tts-models"}
piper_venv=${PAVBOT_PIPER_VENV:-"$HOME/.cache/pavbot/venvs/piper"}
xtts_venv=${PAVBOT_XTTS_VENV:-"$HOME/.cache/pavbot/venvs/xtts"}
python_bin=${PAVBOT_MODEL_PYTHON:-python3}

mkdir -p "$model_dir" "$HOME/.cache/pavbot/venvs"

if ! "$python_bin" -c 'import huggingface_hub' >/dev/null 2>&1; then
  "$python_bin" -m pip install --user huggingface_hub
fi

"$python_bin" - "$model_dir" <<'PY'
import sys
from pathlib import Path
from huggingface_hub import snapshot_download

root = Path(sys.argv[1]).expanduser()
root.mkdir(parents=True, exist_ok=True)

snapshot_download(
    repo_id="rhasspy/piper-voices",
    allow_patterns=[
        "pl/pl_PL/gosia/medium/pl_PL-gosia-medium.onnx",
        "pl/pl_PL/gosia/medium/pl_PL-gosia-medium.onnx.json",
    ],
    local_dir=str(root / "piper-voices"),
)

snapshot_download(
    repo_id="coqui/XTTS-v2",
    allow_patterns=[
        "config.json",
        "model.pth",
        "vocab.json",
        "speakers_xtts.pth",
    ],
    local_dir=str(root / "xtts-v2"),
)
PY

if [[ "${PAVBOT_SKIP_PIPER_RUNTIME:-0}" != "1" ]]; then
  if [[ ! -x "$piper_venv/bin/piper" ]]; then
    python3.12 -m venv "$piper_venv"
    "$piper_venv/bin/python" -m pip install --upgrade pip
    "$piper_venv/bin/python" -m pip install "piper-tts==1.4.2"
  fi
fi

if [[ "${PAVBOT_SETUP_XTTS_RUNTIME:-0}" == "1" ]]; then
  if command -v python3.11 >/dev/null 2>&1; then
    if [[ ! -x "$xtts_venv/bin/python" ]]; then
      python3.11 -m venv "$xtts_venv"
      "$xtts_venv/bin/python" -m pip install --upgrade pip
      "$xtts_venv/bin/python" -m pip install "TTS==0.22.0" "transformers==4.33.3"
    else
      "$xtts_venv/bin/python" -m pip install "transformers==4.33.3"
    fi
  else
    printf 'python3.11 not found; XTTS runtime skipped, model files downloaded\n' >&2
  fi
fi

printf 'local TTS assets ready under %s\n' "$model_dir"
