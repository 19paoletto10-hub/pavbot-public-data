# How To Use Pavbot

Pavbot is a Codex-native research automation workspace. Use it as a small
operating system for topic-based research: each topic has a contract, daily
reports, an index, a backlog, and proposals for risky actions.

## Daily Use

1. Let the scheduled Codex heartbeat run.
2. Read the newest report in `research/tech-news/runs/`.
3. Check `research/tech-news/index.md` for the current summary.
4. Listen to the newest podcast in `research/tech-news/podcasts/`.
5. Add review notes to `research/tech-news/backlog.md`.
6. Read the newest Poland/world report in `research/polska-swiat/runs/`.
7. Listen to the newest Poland/world podcast in
   `research/polska-swiat/podcasts/`.
8. Add review notes to `research/polska-swiat/backlog.md`.
9. Read the newest LLM/AI jobs report in
   `research/llm-ai-jobs-wroclaw/runs/` and PDF in
   `research/llm-ai-jobs-wroclaw/pdfs/`.
10. Keep the first three scheduled runs under manual review before adding more
    topics.

The current active automations are:

- Name: `Pavbot Tech Research 08:00`
- ID: `codex-agent-automation-daily-research`
- Topic: `research/tech-news`
- Cadence: daily at 08:00 local time

- Name: `Pavbot Tech Podcast 09:00`
- ID: `pavbot-tech-podcast-09-00`
- Topic: `research/tech-news`
- Cadence: daily at 09:00 local time
- Output: `research/tech-news/podcasts/YYYY-MM-DD/podcast.mp3`

- Name: `Pavbot Polska Świat Research 08:30`
- ID: `pavbot-polska-wiat-research-08-30`
- Topic: `research/polska-swiat`
- Cadence: daily at 08:30 local time

- Name: `Pavbot Polska Świat Podcast 09:30`
- ID: `pavbot-polska-wiat-podcast-09-30`
- Topic: `research/polska-swiat`
- Cadence: daily at 09:30 local time
- Output: `research/polska-swiat/podcasts/YYYY-MM-DD/podcast.mp3`

- Name: `Pavbot LLM/AI Jobs Wrocław Research`
- ID: `pavbot-llm-ai-jobs-wroclaw-research`
- Topic: `research/llm-ai-jobs-wroclaw`
- Cadence: twice daily; repository reports use `YYYY-MM-DD-HHMM` filenames
- Output: `research/llm-ai-jobs-wroclaw/runs/YYYY-MM-DD-HHMM.md`
- PDF: `research/llm-ai-jobs-wroclaw/pdfs/YYYY-MM-DD-HHMM-llm-ai-jobs-wroclaw.pdf`

## Manual Run

Use a manual run when you want to test the workflow before the next scheduled
heartbeat:

```text
$daily-research-agent

Run one research workflow cycle for `research/tech-news`.
Follow the topic contract, update the report/index/backlog, and use proposals
for any medium-risk or high-risk action.
```

Manual podcast test:

```text
$daily-tech-podcast-agent

Prepare today's Polish technology-news podcast for `research/tech-news` and
write `draft.md`, `script.md`, `sources.md`, `render.json`, `brief.pdf`, and
`podcast.mp3`.
```

Manual Poland/world research test:

```text
$daily-research-agent

Run one research workflow cycle for `research/polska-swiat`.
Follow the topic contract, update the report/index/backlog, and use proposals
for any medium-risk or high-risk action.
```

Manual Poland/world podcast test:

```text
$daily-news-podcast-agent

Prepare today's Polish Poland/world news podcast for `research/polska-swiat`
and write `draft.md`, `script.md`, `sources.md`, `render.json`, `brief.pdf`, and
`podcast.mp3`.
```

Manual LLM/AI jobs research test:

```text
$daily-research-agent

Run one research workflow cycle for `research/llm-ai-jobs-wroclaw`.
Follow the topic contract, update the report/index/backlog, create the PDF, and
use proposals for any medium-risk or high-risk action.
```

Shared local TTS models can be prepared with:

```bash
bash .agents/scripts/podcast/download-local-tts-models.sh
```

Use `PAVBOT_TTS_ENGINE=say|piper|xtts|auto` to choose the renderer. `auto`
falls back from XTTS-v2 to Piper to macOS `say -v Zosia`.

After the run, verify the workspace:

```bash
scripts/verify-research-workspace.sh
```

Each automation should refresh `public/pavbot-manifest.json` after writing
artifacts:

```bash
python3 scripts/generate_pavbot_manifest.py
```

Set `PAVBOT_RAW_BASE_URL` before generation when the manifest should contain
absolute public GitHub raw URLs.

To connect the iOS app to your own Codex-backed repository, follow
`docs/connect-ios-app-to-your-repo.md`. Version 1 expects a public GitHub raw
manifest URL.

## Reviewing The First Three Runs

For each of the first three scheduled reports, add one note to the tech-news
backlog:

```md
- YYYY-MM-DD: Report N review. Source quality: good|mixed|poor.
  Deduplication: good|needs work. Risk gate: passed|needs work. Notes: ...
```

Only scale to more topics when:

- Material claims include links.
- "No material change" reports stay short.
- Repeated findings are not copied forward without new context.
- Risky actions become proposal files instead of direct changes.
- The backlog contains actionable next steps.
- The podcast MP3 is generated, listenable, and based on linked sources.

## Creating A New Topic

1. Choose a lowercase slug, for example `ai-regulation-eu`.
2. Create `research/<slug>/`.
3. Copy the templates:
   - `research/templates/topic-template.md` to `research/<slug>/topic.md`
   - `research/templates/index-template.md` to `research/<slug>/index.md`
   - `research/templates/backlog-template.md` to `research/<slug>/backlog.md`
   - create empty folders `runs/` and `proposals/`
4. Fill out `topic.md` before scheduling anything.
5. Use `research/templates/new-topic-checklist.md` to review readiness.
6. Run the topic manually once.
7. Create a dedicated Codex thread and heartbeat automation only after the
   manual run produces a useful report.

## Working With Proposals

Proposal files live in `research/<topic>/proposals/`. Review them as candidate
changes, not as completed work.

Approve a proposal only when:

- The affected paths are listed.
- The acceptance criteria are clear.
- The rollback is realistic.
- The change does not silently expand agent permissions.

## When To Consider OpenClaw

Stay Codex-native while the pilot is proving report quality. Consider OpenClaw
later if you need a persistent personal assistant, messaging channels,
multi-agent routing, or 24/7 VPS/Mac Mini operation.

Do not install or run OpenClaw from this repository without a separate approval
step. Keep OpenClaw as an optional external runtime that reads Pavbot artifacts
and writes proposals, not as a replacement for the current Codex automation.
