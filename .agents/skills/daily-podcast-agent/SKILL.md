---
name: daily-podcast-agent
description: Use when Codex is asked to create or improve a Pavbot daily podcast package from a research topic, including editorial review, source notes, Polish script quality, local TTS selection, MP3 rendering, and render metadata.
---

# Daily Podcast Agent

Create one broadcast-ready Polish podcast package for a Pavbot topic.

## Inputs

1. Use the topic named by the user, otherwise infer it from the wrapper skill or
   automation prompt.
2. Read, in this order:
   - `AGENTS.md`
   - `docs/architecture.md`
   - `research/<topic>/topic.md`
   - `research/<topic>/index.md`
   - `research/<topic>/backlog.md`
   - `research/<topic>/runs/YYYY-MM-DD.md`, when today's report exists
3. Use today's report as the primary evidence base. If it is missing, perform a
   short fallback public-source check and record the limitation in `sources.md`.

## Editorial Workflow

1. Select 4-6 stories that match the topic contract and have linked evidence.
2. Write `research/<topic>/podcasts/YYYY-MM-DD/draft.md` as a working script.
3. Review every factual claim against `sources.md`. Remove unsupported claims
   instead of softening them into speculation.
4. Rewrite the final `script.md` for spoken Polish:
   - używaj pełnych polskich znaków diakrytycznych: `ą`, `ć`, `ę`, `ł`, `ń`,
     `ó`, `ś`, `ź`, `ż`;
   - avoid raw URLs, Markdown links, bullet-heavy notes, and visual-only cues;
   - expand unclear acronyms on first use;
   - write dates, numbers, currencies, and names in a form that TTS can read
     naturally;
   - include smooth transitions, short context, and why each item matters.
5. Write `sources.md` with three sections:
   - `## Źródła użyte w scenariuszu`
   - `## Źródła sprawdzone, ale niewykorzystane`
   - `## Źródła niedostępne lub niejednoznaczne`
6. Run the editorial lint before rendering:

```bash
bash .agents/scripts/podcast/editorial_lint.sh \
  research/<topic>/podcasts/YYYY-MM-DD/script.md \
  research/<topic>/podcasts/YYYY-MM-DD/sources.md
```

## Audio Rendering

Use the shared renderer, not a topic-local copy:

```bash
bash .agents/scripts/podcast/render-podcast-audio.sh \
  research/<topic>/podcasts/YYYY-MM-DD/script.md \
  research/<topic>/podcasts/YYYY-MM-DD/podcast.mp3
```

The renderer writes `render.json` next to the MP3. Use
`PAVBOT_TTS_ENGINE=say|piper|xtts|auto` to choose the backend. Default `auto`
tries XTTS-v2, then Piper, then macOS `say -v Zosia`.

Local model files live outside the repository in `~/.cache/pavbot/tts-models`.
Download them with:

```bash
bash .agents/scripts/podcast/download-local-tts-models.sh
```

`PAVBOT_TTS_VOICE_SAMPLE=/path/to/sample.wav` is reserved for later voice
sample support. Do not require voice cloning for the default workflow.

## PDF Brief

After `render.json` exists, create a professional PDF brief with the discovered
information, source links, and audio metadata:

```bash
~/.cache/pavbot/venvs/pdf/bin/python \
  .agents/scripts/podcast/render-podcast-brief-pdf.py \
  research/<topic>/podcasts/YYYY-MM-DD
```

The PDF should be premium mobile-first output: 390 x 844 pt pages, readable in
the Pavbot iOS app without manual zoom, with clear typography, compact audio
metadata cards, visible source links, and no raw URL clutter in the main body.
Render the PDF pages to PNG and visually check spacing, page numbers, Polish
characters, source links, and clipped or overlapping text before claiming
success.

## Output Contract

Create these files:

- `research/<topic>/podcasts/YYYY-MM-DD/draft.md`
- `research/<topic>/podcasts/YYYY-MM-DD/script.md`
- `research/<topic>/podcasts/YYYY-MM-DD/sources.md`
- `research/<topic>/podcasts/YYYY-MM-DD/render.json`
- `research/<topic>/podcasts/YYYY-MM-DD/brief.pdf`
- `research/<topic>/podcasts/YYYY-MM-DD/podcast.mp3`

Target duration is 7:30-8:30, verified with `ffprobe` as 450-510 seconds. If
the first render is outside that range, revise `script.md` and render again.

If all TTS backends fail, do not fake the MP3. Keep `script.md` and
`sources.md`, record the failure in `render.json` or `sources.md`, and add a
backlog note inside the active topic.

## Public iOS Publication

When the episode is part of a Pavbot automation, finish by publishing the topic
outputs. The episode is not complete until the refreshed
`public/pavbot-manifest.json` and the episode artifacts are pushed to
`origin/main`:

```bash
scripts/pavbot_commit_and_push_outputs.sh --isolated research/<topic>
```

The publish script derives `PAVBOT_MANIFEST_URL` from an explicit environment
override, `PAVBOT_RAW_BASE_URL`, the existing manifest `rawBaseUrl`, or the
GitHub `origin` remote. The resolved URL must match the public raw manifest URL
used in iOS `Settings -> Manifest URL`; the iOS app does not send this value
back to Codex. The publish script runs `python3 scripts/generate_pavbot_manifest.py`
in a temporary clean worktree, commits only generated outputs (`runs/`, `pdfs`,
`podcasts/`, `index.md`, `backlog.md`) plus `public/pavbot-manifest.json`, and
pushes to `origin/main`.
After publishing, run `git fetch origin` and verify that
`origin/main:public/pavbot-manifest.json` contains the current episode paths and
that those files exist on `origin/main`. If this verification fails, report the
episode as failed or partially published instead of successful.
Never publish topic `tools/`, prompt edits, app code, docs, backend code, or
other development changes as automation outputs.
