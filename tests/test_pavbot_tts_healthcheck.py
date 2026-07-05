from __future__ import annotations

import json
import os
import stat
import subprocess
import sys
import tempfile
from pathlib import Path


SCRIPT = Path(__file__).resolve().parents[1] / "scripts" / "pavbot_tts_healthcheck.sh"


def write_executable(path: Path, text: str) -> None:
    path.write_text(text, encoding="utf-8")
    path.chmod(path.stat().st_mode | stat.S_IXUSR)


def test_tts_healthcheck_runs_shared_renderer_without_mobile_xtts() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        fake_bin = root / "bin"
        fake_renderer = root / "renderer.sh"
        output = root / "health.json"
        fake_bin.mkdir()

        write_executable(
            fake_renderer,
            """#!/usr/bin/env bash
set -euo pipefail
output=$2
mkdir -p "$(dirname "$output")"
printf 'mp3' > "$output"
""",
        )
        write_executable(
            fake_bin / "ffprobe",
            "#!/usr/bin/env bash\nprintf '1.25\\n'\n",
        )

        env = os.environ.copy()
        env["PATH"] = f"{fake_bin}:{env['PATH']}"
        env["PAVBOT_SHARED_RENDERER"] = str(fake_renderer)
        env["PAVBOT_PYTHON"] = sys.executable

        result = subprocess.run(
            ["bash", str(SCRIPT), "--output", str(output)],
            capture_output=True,
            text=True,
            check=False,
            env=env,
        )

        assert result.returncode == 0, result.stderr
        payload = json.loads(output.read_text(encoding="utf-8"))
        assert payload["status"] == "ok"
        assert payload["checks"][0]["engine"] == "piper"
        assert "male-xtts" not in output.read_text(encoding="utf-8")
