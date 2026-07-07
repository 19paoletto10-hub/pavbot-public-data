#!/usr/bin/env python3
"""Render Polish speech with a local Coqui XTTS-v2 checkout.

This script is intentionally small and defensive. The shell renderer decides
whether XTTS is available; this module only turns a cleaned text file into WAV.
"""

from __future__ import annotations

import os
import sys
from pathlib import Path


def fail(message: str, code: int = 69) -> None:
    print(message, file=sys.stderr)
    raise SystemExit(code)


def main() -> None:
    os.environ.setdefault("TORCH_FORCE_NO_WEIGHTS_ONLY_LOAD", "1")

    if len(sys.argv) != 4:
        fail("usage: render_xtts.py SPOKEN_TEXT OUTPUT_WAV XTTS_MODEL_DIR", 64)

    text_path = Path(sys.argv[1])
    output_wav = Path(sys.argv[2])
    model_dir = Path(sys.argv[3])

    if not text_path.is_file():
        fail(f"spoken text not found: {text_path}", 66)

    config = model_dir / "config.json"
    model = model_dir / "model.pth"
    vocab = model_dir / "vocab.json"
    speakers = model_dir / "speakers_xtts.pth"
    missing = [p for p in (config, model, vocab, speakers) if not p.is_file()]
    if missing:
        fail("missing XTTS model files: " + ", ".join(str(p) for p in missing), 69)

    try:
        from TTS.api import TTS
    except Exception as exc:  # pragma: no cover - depends on optional venv
        fail(f"Coqui TTS runtime is not available: {exc}", 69)

    text = text_path.read_text(encoding="utf-8").strip()
    if not text:
        fail(f"spoken text is empty: {text_path}", 65)

    output_wav.parent.mkdir(parents=True, exist_ok=True)

    voice_sample = os.environ.get("PAVBOT_TTS_VOICE_SAMPLE", "").strip()
    requested_speaker = os.environ.get("PAVBOT_XTTS_SPEAKER", "").strip()

    try:
        tts = TTS(
            model_path=str(model_dir),
            config_path=str(config),
            progress_bar=False,
            gpu=False,
        )
    except Exception as exc:  # pragma: no cover - optional runtime
        fail(f"failed to load XTTS-v2: {exc}", 69)

    kwargs: dict[str, object] = {
        "text": text,
        "file_path": str(output_wav),
        "language": os.environ.get("PAVBOT_XTTS_LANGUAGE", "pl"),
    }

    if voice_sample:
        sample = Path(voice_sample)
        if not sample.is_file():
            fail(f"voice sample not found: {sample}", 66)
        kwargs["speaker_wav"] = str(sample)
    else:
        speaker = requested_speaker
        if not speaker:
            available = list(getattr(tts, "speakers", None) or [])
            if not available:
                model_obj = getattr(getattr(tts, "synthesizer", None), "tts_model", None)
                speaker_manager = getattr(model_obj, "speaker_manager", None)
                speakers_obj = getattr(speaker_manager, "speakers", None)
                if isinstance(speakers_obj, dict):
                    available = list(speakers_obj.keys())
                if not available:
                    name_to_id = getattr(speaker_manager, "name_to_id", None)
                    if name_to_id is not None:
                        available = list(name_to_id)
            if available:
                speaker = "Ana Florence" if "Ana Florence" in available else str(available[0])
        if speaker:
            kwargs["speaker"] = speaker

    try:
        tts.tts_to_file(**kwargs)
    except Exception as exc:  # pragma: no cover - optional runtime
        fail(f"XTTS render failed: {exc}", 69)

    if not output_wav.is_file() or output_wav.stat().st_size == 0:
        fail(f"XTTS did not create audio: {output_wav}", 70)


if __name__ == "__main__":
    main()
