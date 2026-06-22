# Pavbot Research Automation Architecture

## Summary

Pavbot MVP is a hybrid Codex automation system. Codex provides the agent runtime,
thread context, tools, skills, and recurring wakeups. This repository provides
the durable operating state: topic contracts, reports, indexes, backlog, and
reviewable proposals.

## Runtime Model

- Each research topic has one or more dedicated Codex heartbeat threads. Codex
  allows one active heartbeat per thread, so research and podcast heartbeats can
  use separate dedicated threads for the same topic.
- The active `tech-news` topic uses an 08:00 research heartbeat and a 09:00
  podcast heartbeat. The active `polska-swiat` topic uses an 08:30 research
  heartbeat and a 09:30 podcast heartbeat. The active
  `llm-ai-jobs-wroclaw` topic uses twice-daily research heartbeats with
  timestamped report and PDF outputs.
- Research heartbeats invoke `daily-research-agent`. Podcast heartbeats invoke
  a thin topic-specific wrapper, which delegates editorial review and audio
  rendering to `daily-podcast-agent`.
- The agent writes dated reports and updates the topic index/backlog.
- Risk-gated actions are saved as proposals and left for human review.

## Data Model

- `topic.md` defines the topic contract.
- `runs/YYYY-MM-DD.md` stores a daily run report.
- `index.md` stores the current state of knowledge.
- `backlog.md` stores questions, follow-ups, and candidate actions.
- `proposals/*.md` stores changes that require approval.
- `pdfs/YYYY-MM-DD-<topic>.pdf` stores the professional PDF version of a daily
  research report.
- Topics with more than one daily run can use timestamped report and PDF names,
  for example `YYYY-MM-DD-HHMM.md` and `YYYY-MM-DD-HHMM-<topic>.pdf`.
- `podcasts/YYYY-MM-DD/` stores podcast scripts, source notes, and MP3 files
  when a topic has an audio automation.
- Podcast packages also include `draft.md` and `render.json` when generated
  through the shared podcast pipeline.
- Podcast packages include `brief.pdf`, a professional PDF summary of the
  discovered information, sources, and audio metadata.
- `public/pavbot-manifest.json` stores the read-only public index consumed by
  the iOS viewer. It is generated from the docs and `research/<topic>/`
  artifacts by `scripts/generate_pavbot_manifest.py`.

## Podcast Audio

- All topics use `.agents/scripts/podcast/render-podcast-audio.sh` for MP3
  creation.
- `PAVBOT_TTS_ENGINE=auto` tries XTTS-v2, then Piper, then macOS `say -v Zosia`.
- Local model files live in `~/.cache/pavbot/tts-models`, outside the
  repository.
- `PAVBOT_TTS_VOICE_SAMPLE` is reserved for a future explicit voice sample; the
  default workflow does not require voice cloning.

## Risk Gate

Low-risk actions may be performed directly:

- Create a daily report inside the active topic.
- Create a professional PDF version of a daily report inside the active topic.
- Create a podcast script, source note, or generated MP3 inside the active
  topic.
- Update the active topic index.
- Add or close backlog items inside the active topic.
- Record source links and short notes.

Medium-risk and high-risk actions must be proposals:

- Add or modify automations.
- Modify skills, hooks, MCP config, or repo-level instructions.
- Change files outside the active topic.
- Run destructive commands or broad filesystem operations.
- Make product, legal, financial, medical, or security recommendations that
  would require expert review.

## V2 Server Path

When the local MVP is stable, add a lightweight server orchestrator using
Node.js 20 and the Codex SDK. The server should own queueing, retries, logs,
and deployment on VPS/Docker while reusing the same topic files and skill.

## Optional OpenClaw Observer

OpenClaw can be evaluated after the Codex-native pilot has three reviewed daily
reports. Use it as a separate observer runtime, not as the primary writer for
this repository. Keep OpenClaw workspace, credentials, sessions, and state
outside the repo, and give it read-only access to Pavbot research artifacts
until its behavior has been reviewed.
