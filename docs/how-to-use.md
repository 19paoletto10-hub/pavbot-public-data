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
10. Read the newest mobile current-events brief in
    `research/aktualne-wydarzenia-mobile/pdfs/` and compare both TTS variants
    in `research/aktualne-wydarzenia-mobile/podcasts/`.
11. Keep the first three scheduled runs under manual review before adding more
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

- Name: `Pavbot Aktualne Wydarzenia Mobile 10:15`
- ID: `pavbot-aktualne-wydarzenia-mobile-10-15`
- Kind: `researchAudio`
- Topic: `research/aktualne-wydarzenia-mobile`
- Cadence: daily at 10:15 local time
- Output: `research/aktualne-wydarzenia-mobile/pdfs/YYYY-MM-DD-HHMM-mobile-brief.pdf`
- Newspaper PDF: `research/aktualne-wydarzenia-mobile/pdfs/YYYY-MM-DD-HHMM-newspaper.pdf`
- Report: `research/aktualne-wydarzenia-mobile/runs/YYYY-MM-DD-HHMM.md`
- Podcast package: `research/aktualne-wydarzenia-mobile/podcasts/YYYY-MM-DD-HHMM/`
- Audio variants: `research/aktualne-wydarzenia-mobile/podcasts/YYYY-MM-DD-HHMM/audio/<variant>/podcast.mp3`

- Name: `Pavbot Puls Dnia 3h`
- ID: `pavbot-puls-dnia-news-3h`
- Kind: `automation`
- Topic: `research/puls-dnia-news`
- Cadence: 06:00, 09:00, 12:00, 15:00, 18:00 and 21:00 Europe/Warsaw
- Output: `research/puls-dnia-news/data/YYYY-MM-DD-HHMM-pulse-news.json`
- Report: `research/puls-dnia-news/runs/YYYY-MM-DD-HHMM.md`
- iOS surface: `Puls Dnia` tab
- iOS retention: fetched runs are cached locally for 48 hours; saved news stay
  local until the user removes them.

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

Run one research workflow cycle for `research/llm-ai-jobs-wroclaw`: create the
timestamped Markdown report in `runs/YYYY-MM-DD-HHMM.md`, create the mandatory
structured Jobs artifact in `data/YYYY-MM-DD-HHMM-jobs.json` with
`render_jobs_data.py`, validate it with `scripts/validate_jobs_data.py`,
generate the PDF in
`pdfs/YYYY-MM-DD-HHMM-llm-ai-jobs-wroclaw.pdf`, then publish with
`scripts/pavbot_commit_and_push_outputs.sh --isolated research/llm-ai-jobs-wroclaw`.
After publish, run `git fetch origin` and verify
`origin/main:public/pavbot-manifest.json` plus the matching `runs/`, `data/`,
and `pdfs/` package for the same `YYYY-MM-DD-HHMM`.
Follow the topic contract and use proposals for any medium-risk or high-risk
action.
```

Manual mobile current-events brief test:

```text
$daily-research-agent

Run the complete mobile current-events workflow for
`research/aktualne-wydarzenia-mobile`: create one Europe/Warsaw timestamp with
`RUN_STAMP=$(TZ=Europe/Warsaw date +%Y-%m-%d-%H%M)` and
`RUN_DATE=${RUN_STAMP:0:10}`, then create the timestamped Markdown report in
`runs/YYYY-MM-DD-HHMM.md`, mobile PDF in
`pdfs/YYYY-MM-DD-HHMM-mobile-brief.pdf`, newspaper PDF in
`pdfs/YYYY-MM-DD-HHMM-newspaper.pdf`, podcast package in
`podcasts/YYYY-MM-DD-HHMM/`, public `script.md` for local iPhone TTS, both MP3
TTS variants when available, and `tts_variants.json`.
```

Shared local TTS models can be prepared with:

```bash
bash .agents/scripts/podcast/download-local-tts-models.sh
```

Use `PAVBOT_TTS_ENGINE=say|piper|xtts|auto` to choose the renderer. `auto`
falls back from XTTS-v2 to Piper to macOS `say -v Zosia`.

In the iOS app, audio artifacts can keep playing after switching tabs,
minimizing the app, or locking the iPhone. The active audio item also exposes
Now Playing controls and, on supported devices, a Live Activity/Dynamic Island
entry that deep-links back to the artifact.
For `Research -> Aktualne`, the iOS app can also read the published podcast
`script.md` locally with native iPhone TTS, so the text path still works when a
server-rendered MP3 variant is missing.

Manual pulse-news test:

```text
$daily-research-agent

Run the `Pavbot Puls Dnia 3h` workflow for `research/puls-dnia-news`: create
one Europe/Warsaw timestamp, write `runs/YYYY-MM-DD-HHMM.md`, write
`data/YYYY-MM-DD-HHMM-pulse-news.json` with at least 12 sourced news items and
an even item count, validate it with `scripts/validate_pulse_news_data.py`, and
publish with `scripts/pavbot_commit_and_push_outputs.sh --isolated
research/puls-dnia-news`.
```

In the iOS app, `Puls Dnia` shows the latest published `pulseNewsData` and keeps
a local 48-hour history for smooth browsing. A news item saved by the user
disappears from the active carousel, remains in `Zapisane`, and is not removed
by the 48-hour cleanup.

In `Ustawienia`, use `Przywróć ustawienia domyślne` when the Manifest URL or
Notification server URL is stale. The app calls the notifier endpoint
`/v1/app/defaults`, fills the current GitHub raw manifest URL and Cloudflare
notifier URL, then reloads the manifest. If a Quick Tunnel URL changes, update
`PAVBOT_PUBLIC_NOTIFIER_URL`, restart the notifier, and tap this button in the
app.

After the run, verify the workspace:

```bash
scripts/verify-research-workspace.sh
```

Each automation should publish its topic output after writing artifacts. The
publish script automatically derives the public manifest URL from
`PAVBOT_MANIFEST_URL`, `PAVBOT_RAW_BASE_URL`, the existing manifest `rawBaseUrl`,
or the GitHub `origin` remote. Set `PAVBOT_MANIFEST_URL` only when you need to
override the default URL used by iOS `Settings -> Manifest URL`:

```bash
# Optional override:
# export PAVBOT_MANIFEST_URL="https://raw.githubusercontent.com/<owner>/<repo>/<branch>/public/pavbot-manifest.json"
scripts/pavbot_commit_and_push_outputs.sh --isolated research/<topic>
```

The isolated publish script creates a temporary clean worktree from
`origin/main`, copies only generated outputs from the active topic, runs
`python3 scripts/generate_pavbot_manifest.py`, commits the refreshed manifest
with the outputs, and pushes directly to `origin/main`. Treat this as the
single publish step after each automation run so iOS receives the refreshed
manifest and the new files in the same commit. After the push, run
`git fetch origin` and verify `origin/main:public/pavbot-manifest.json`; for
Jobs, also verify the same package key is present remotely as `run`, `jobsData`,
and `pdf`. This requires:

- a working `origin` remote;
- GitHub credentials or a token with permission to push to `main`;
- either an auto-resolvable GitHub `origin` or an explicit `PAVBOT_MANIFEST_URL`.

Only `runs/`, `data/`, `pdfs/`, `podcasts/`, `index.md`, `backlog.md`, and
`public/pavbot-manifest.json` are publishable as automation outputs. Code,
docs, prompt edits, topic tools, iOS changes, and backend changes must go
through a separate development branch/commit.

The iOS app reads this URL but does not send it back to Codex automations. For
advanced compatibility, `PAVBOT_RAW_BASE_URL` and `--raw-base-url` still work;
the publish script also uses `PAVBOT_RAW_BASE_URL` to derive the manifest URL
when `PAVBOT_MANIFEST_URL` is unset.

To connect the iOS app to your own Codex-backed repository, follow
`docs/connect-ios-app-to-your-repo.md`. Version 1 expects a public GitHub raw
manifest URL.

For optional live iOS notifications without a VPS, run the notifier on your
MacBook and expose it with Cloudflare Tunnel:
`docs/live-ios-notifications-macbook-cloudflare.md`. The app remains a reader:
it does not configure Codex automations by itself, and the MacBook must stay
awake for live webhook-driven push alerts to work. Push alerts are triggered by
GitHub `push` webhooks, so the automation must publish to GitHub before the
notifier can detect new files.

When the iOS app is closed, only real APNs pushes can deliver an alert. If
Docker, Cloudflare Tunnel, GitHub webhook delivery, or APNs configuration is
down, the app will not receive a live notification until it is opened and
manually refreshed.

## iOS Release

The current iOS marketing version is `1.5`. The app and Live Activity extension
read this from `ios/PavbotViewer/project.yml` through XcodeGen. Build numbers
are still automatic through the `Set Dynamic Build Number` build phase.

For TestFlight or App Store Connect release steps, use
`docs/ios-appstore-release.md`.

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
