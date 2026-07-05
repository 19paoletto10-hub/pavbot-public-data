from __future__ import annotations

import json
import os
import stat
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


class MobileTtsAudioTest(unittest.TestCase):
    def setUp(self) -> None:
        self.repo_root = Path(__file__).resolve().parents[1]
        self.script_path = (
            self.repo_root
            / "research"
            / "aktualne-wydarzenia-mobile"
            / "tools"
            / "render_mobile_tts_audio.sh"
        )

    def test_renders_only_required_female_piper_variant(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            script_md = root / "script.md"
            podcast_dir = root / "podcast"
            fake_bin = root / "bin"
            fake_renderer = root / "fake-renderer.sh"
            script_md.write_text(
                "Dzień dobry. To jest polski test lektora dla Pavbota.\n",
                encoding="utf-8",
            )
            fake_bin.mkdir()
            self.write_executable(
                fake_renderer,
                """#!/usr/bin/env bash
set -euo pipefail
output=$2
mkdir -p "$(dirname "$output")"
printf 'raw mp3' > "$output"
render_json="$(dirname "$output")/render.json"
cat > "$render_json" <<JSON
{"engine_used":"piper","model":"fake-piper","duration_seconds":130.0}
JSON
""",
            )
            self.write_executable(
                fake_bin / "ffmpeg",
                """#!/usr/bin/env bash
set -euo pipefail
input=""
output="${@: -1}"
while (($#)); do
  if [[ "$1" == "-i" ]]; then
    shift
    input=$1
  fi
  shift || true
done
cp "$input" "$output"
""",
            )
            self.write_executable(
                fake_bin / "ffprobe",
                "#!/usr/bin/env bash\nprintf '125.50\\n'\n",
            )

            env = os.environ.copy()
            env["PATH"] = f"{fake_bin}:{env['PATH']}"
            env["PAVBOT_SHARED_RENDERER"] = str(fake_renderer)
            env["PAVBOT_PYTHON"] = sys.executable

            result = subprocess.run(
                ["bash", str(self.script_path), str(script_md), str(podcast_dir)],
                cwd=self.repo_root,
                env=env,
                capture_output=True,
                text=True,
                check=False,
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertTrue((podcast_dir / "audio" / "female-piper" / "podcast.mp3").is_file())
            self.assertFalse((podcast_dir / "audio" / "male-xtts").exists())
            tts_variants = json.loads((podcast_dir / "tts_variants.json").read_text(encoding="utf-8"))
            self.assertEqual([variant["id"] for variant in tts_variants["variants"]], ["female-piper"])
            self.assertEqual(tts_variants["variants"][0]["status"], "ok")

    def test_fails_clearly_when_ffmpeg_is_missing(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            script_md = root / "script.md"
            podcast_dir = root / "podcast"
            fake_bin = root / "bin"
            fake_renderer = root / "fake-renderer.sh"
            script_md.write_text("Dzień dobry.\n", encoding="utf-8")
            fake_bin.mkdir()
            self.write_executable(
                fake_renderer,
                """#!/usr/bin/env bash
set -euo pipefail
output=$2
mkdir -p "$(dirname "$output")"
printf 'raw mp3' > "$output"
""",
            )
            self.write_executable(
                fake_bin / "ffprobe",
                "#!/usr/bin/env bash\nprintf '125.50\\n'\n",
            )

            env = os.environ.copy()
            env["PATH"] = str(fake_bin)
            env["PAVBOT_SHARED_RENDERER"] = str(fake_renderer)
            env["PAVBOT_PYTHON"] = sys.executable

            result = subprocess.run(
                ["/bin/bash", str(self.script_path), str(script_md), str(podcast_dir)],
                cwd=self.repo_root,
                env=env,
                capture_output=True,
                text=True,
                check=False,
            )

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("required command not found: ffmpeg", result.stderr)

    def write_executable(self, path: Path, text: str) -> None:
        path.write_text(text, encoding="utf-8")
        path.chmod(path.stat().st_mode | stat.S_IXUSR)


if __name__ == "__main__":
    unittest.main()
