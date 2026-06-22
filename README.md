# Pavbot Research Automation

Pavbot is a local-first research automation workspace for Codex. The MVP uses
Codex threads and automations as the agent runtime, while this repository stores
topic contracts, reports, indexes, backlog items, proposals, and reusable agent
instructions.

## MVP Shape

- One research topic maps to one or more Codex heartbeat threads. Codex allows
  one active heartbeat per thread, so separate research and podcast heartbeats
  may use separate dedicated threads for the same topic.
- Research outputs are Markdown files under `research/<topic>/`.
- Research outputs also include professional PDF briefs under
  `research/<topic>/pdfs/` when the PDF renderer is available.
- Low-risk updates can be written directly to the topic folder.
- Medium-risk and high-risk actions are written as proposals for review.
- The historical pilot topic is `codex-agent-automation`.
- The active daily news topic is `tech-news`.
- The active general-news topic is `polska-swiat`.

## Repository Map

- `.agents/skills/daily-research-agent/` - reusable Codex skill used by
  research automations.
- `.agents/skills/daily-tech-podcast-agent/` - reusable Codex skill that turns
  daily tech research into a Polish MP3 podcast through the shared podcast
  workflow.
- `.agents/skills/daily-news-podcast-agent/` - reusable Codex skill that turns
  Poland/world public-news research into a Polish MP3 podcast through the
  shared podcast workflow.
- `.agents/skills/daily-podcast-agent/` - shared editorial and local TTS
  workflow for all Pavbot podcast topics.
- `.agents/scripts/podcast/` - shared local podcast rendering tools, including
  macOS `say`, Piper, optional XTTS-v2 backends, and PDF brief generation.
- `docs/` - architecture, SDLC, and automation operating notes.
- `docs/todo.md` - staged TODO list for the MVP and V2 path.
- `docs/how-to-use.md` - daily operating guide for manual runs, reviews, and
  new topics.
- `integrations/openclaw/` - optional OpenClaw observer documentation and safe
  sample workspace files.
- `research/templates/` - canonical Markdown templates.
- `research/codex-agent-automation/` - historical Codex automation pilot topic.
- `research/tech-news/` - active daily technology research and podcast topic.
- `research/polska-swiat/` - active daily Poland/world news and podcast topic.

## Operating Loop

1. Keep each topic scoped in `topic.md`.
2. Run the daily research agent manually before scheduling a topic.
3. Review the first three scheduled reports.
4. Promote repeated manual changes into the skill or templates.
5. Add new topics only after the pilot produces stable, useful reports.
