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
- The `aktualne-wydarzenia-mobile` cron combines a timestamped research
  report, a mobile-first PDF brief, a detailed mobile newspaper PDF, and two
  local TTS MP3 variants in one topic-scoped run.
- The `puls-dnia-news` cron runs every three hours during the day and publishes
  structured `pulseNewsData` for the iOS `Puls Dnia` tab.
- The iOS viewer owns podcast playback through a global audio service, so audio
  artifacts can continue across tab changes, backgrounding, Lock Screen
  controls, and Live Activity/Dynamic Island state.
- The iOS viewer locally caches fetched `pulseNewsData` runs for 48 hours.
  Unsaved pulse news older than 48 hours are pruned on the device, while
  manually saved news stay in local storage without that retention limit.
- The iOS viewer also stores saved Research articles locally for the
  `Polska` and `Świat` sections of `Polska i Świat`; this is an on-device
  reading list and is not synchronized to GitHub or the notifier.
- The iOS weather screen may request approximate current location at refresh
  time. If permission is denied or unavailable, the app falls back to Wrocław.
- The agent writes dated reports and updates the topic index/backlog.
- Risk-gated actions are saved as proposals and left for human review.

## Data Model

- `topic.md` defines the topic contract.
- `runs/YYYY-MM-DD.md` stores a daily run report.
- `index.md` stores the current state of knowledge.
- `backlog.md` stores questions, follow-ups, and candidate actions.
- `proposals/*.md` stores changes that require approval.
- `pdfs/YYYY-MM-DD-<topic>.pdf` stores the mobile-first professional PDF
  version of a daily research report, optimized for review in the Pavbot iOS
  app.
- Topics with more than one daily run can use timestamped report and PDF names,
  for example `YYYY-MM-DD-HHMM.md` and `YYYY-MM-DD-HHMM-<topic>.pdf`.
- `podcasts/YYYY-MM-DD/` stores podcast scripts, source notes, and MP3 files
  when a topic has an audio automation.
- Mobile brief topics use one Europe/Warsaw timestamp per run. Their report,
  PDFs, and podcast package use `YYYY-MM-DD-HHMM` names, including
  `pdfs/YYYY-MM-DD-HHMM-mobile-brief.pdf`,
  `pdfs/YYYY-MM-DD-HHMM-newspaper.pdf`,
  `podcasts/YYYY-MM-DD-HHMM/audio/<variant>/podcast.mp3`, and
  `tts_variants.json`.
- Podcast packages also include `draft.md` and `render.json` when generated
  through the shared podcast pipeline.
- Podcast packages include `brief.pdf`, a professional PDF summary of the
  discovered information, sources, and audio metadata.
- `public/pavbot-manifest.json` stores the read-only public index consumed by
  the iOS viewer. It is generated from the docs and `research/<topic>/`
  artifacts by `scripts/generate_pavbot_manifest.py`.
- `research/puls-dnia-news/data/YYYY-MM-DD-HHMM-pulse-news.json` stores the
  structured pulse-news feed. The iOS app reads it as `pulseNewsData`, shows it
  in the `Puls Dnia` tab, and keeps a local 48-hour history for smooth
  offline/poor-network reading.

## iOS Viewer

- Bundle ID: `com.paweltanski.pavbotviewer`.
- Current marketing version: `1.5`.
- `CFBundleVersion` is set dynamically during build from `PAVBOT_BUILD_NUMBER`
  or the latest git commit timestamp, so TestFlight uploads get increasing
  build numbers.
- Top-level tabs are `Dzisiaj`, `Puls Dnia`, `Jobs`, `Research`, and
  `Ustawienia`.
- `Puls Dnia` first shows the latest run from the public manifest, falls back
  to the local 48-hour cache when refresh fails, and hides locally saved news
  from the active carousel.
- Appearance is user-selectable in `Ustawienia`: system, light, or dark.
- A global mini-player appears when a podcast/audio artifact is active, so
  playback can be controlled while browsing other tabs.

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
- Create a mobile-first professional PDF version of a daily report inside the
  active topic.
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
