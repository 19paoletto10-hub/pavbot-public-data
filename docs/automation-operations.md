# Automation Operations

## Daily Tech Research Automation Prompt

Use this prompt body for the 08:00 technology research heartbeat. Keep schedule,
workspace, and target thread configuration outside the prompt.

```text
$daily-research-agent

Uruchom codzienny research technologiczny dla `research/tech-news`.
Pracuj po polsku i używaj poprawnych polskich znaków. Sprawdź publiczne źródła
dotyczące globalnych newsów technologicznych, AI, startupów, produktów i
regulacji. Zapisz raport do `research/tech-news/runs/YYYY-MM-DD.md` i dodaj sekcję "Tematy do podcastu"
z 5-8 kandydatami.
```

## Daily Tech Podcast Automation Prompt

Use this prompt body for the 09:00 podcast heartbeat.

```text
$daily-tech-podcast-agent

Przygotuj dzisiejszy polski podcast technologiczny dla `research/tech-news`.
Użyj dzisiejszego raportu, sprawdź publiczne źródła newsowe, używaj pełnych
polskich znaków diakrytycznych i zapisz
`draft.md`, `script.md`, `sources.md`, `render.json`, `brief.pdf` i `podcast.mp3` w
`research/tech-news/podcasts/YYYY-MM-DD/`.
```

## Active Automations

- `Pavbot Tech Research 08:00` runs daily at 08:00 Europe/Warsaw and updates
  `research/tech-news`.
- `Pavbot Tech Podcast 09:00` runs daily at 09:00 Europe/Warsaw and creates the
  MP3 podcast package from the morning research.
- `Pavbot Polska Świat Research 08:30` runs daily at 08:30 Europe/Warsaw and
  updates `research/polska-swiat`. ID: `pavbot-polska-wiat-research-08-30`.
- `Pavbot Polska Świat Podcast 09:30` runs daily at 09:30 Europe/Warsaw and
  creates the MP3 podcast package from the Poland/world morning research. ID:
  `pavbot-polska-wiat-podcast-09-30`.
- `Pavbot LLM/AI Jobs Wrocław Research` runs twice daily and updates
  `research/llm-ai-jobs-wroclaw` with the full flow `Markdown -> jobsData JSON
  -> validate -> PDF -> publish`. The published package must expose matching
  `runs/YYYY-MM-DD-HHMM.md`, `data/YYYY-MM-DD-HHMM-jobs.json`, and
  `pdfs/YYYY-MM-DD-HHMM-llm-ai-jobs-wroclaw.pdf` entries for the same package
  key on `origin/main`. Repository manifest ID:
  `pavbot-llm-ai-jobs-wroclaw-research`.
- `Pavbot Aktualne Wydarzenia Mobile 10:15` runs daily at 10:15 Europe/Warsaw
  and updates `research/aktualne-wydarzenia-mobile` with one timestamped
  package: `runs/YYYY-MM-DD-HHMM.md`, `pdfs/YYYY-MM-DD-HHMM-mobile-brief.pdf`,
  `pdfs/YYYY-MM-DD-HHMM-newspaper.pdf`, `podcasts/YYYY-MM-DD-HHMM/`, female
  Piper MP3, male XTTS MP3, script, sources, and variant metadata. ID:
  `pavbot-aktualne-wydarzenia-mobile-10-15`.
- `Pavbot Puls Dnia 3h` runs at 06:00, 09:00, 12:00, 15:00, 18:00 and 21:00
  Europe/Warsaw and updates `research/puls-dnia-news` with a timestamped
  Markdown report plus `data/YYYY-MM-DD-HHMM-pulse-news.json`. ID:
  `pavbot-puls-dnia-news-3h`.
- `Pavbot Reddit Safari Humor Radar` runs at 00:06, 02:06, 04:06, 06:06,
  08:06, 10:06, 12:06, 14:06, 16:06, 18:06, 20:06 and 22:06 Europe/Warsaw.
  It uses the logged-in local Safari session to publish `Śmiechowy radar`
  data to `https://notify.paweltanski.com/v1/humor/digest`. ID:
  `pavbot-reddit-safari-humor-radar`.

## Publishing Contract

Every active automation must finish with the shared publication script:

```bash
# Optional override when origin/rawBaseUrl cannot derive the right public URL:
# export PAVBOT_MANIFEST_URL="https://raw.githubusercontent.com/<owner>/<repo>/<branch>/public/pavbot-manifest.json"
scripts/pavbot_commit_and_push_outputs.sh --isolated research/<topic>
```

The isolated script creates a temporary clean worktree from `origin/main`,
copies only generated outputs from the active topic, refreshes
`public/pavbot-manifest.json`, commits those files, and pushes to
`origin/main`. It derives the public manifest URL from `PAVBOT_MANIFEST_URL`,
`PAVBOT_RAW_BASE_URL`, the existing manifest `rawBaseUrl`, or the GitHub
`origin` remote. It requires a working `origin` and push credentials for
`main`. Do not push generated automation files separately from the refreshed
manifest. The GitHub webhook for live iOS notifications fires only after this
push succeeds.

Treat `git push` as necessary but not sufficient. Run `git fetch origin` and
verify `origin/main:public/pavbot-manifest.json` before declaring success. For
Jobs, success means the current package key is visible on `origin/main` as a
complete set of `run`, `jobsData`, and `pdf` artifacts, not just as a local
commit.

Automation output commits may include only `runs/`, `data/`, `pdfs/`, `podcasts/`,
`index.md`, `backlog.md`, and `public/pavbot-manifest.json`. App code, docs,
prompt edits, and topic `tools/` changes are development work and must be
committed separately.

## First Three Runs Review

For the first three scheduled runs, review:

- Source quality and whether claims are linked.
- Whether repeated findings were deduplicated.
- Whether "No material change" reports stay short.
- Whether risky actions became proposals.
- Whether backlog items are specific enough to act on.
- Whether the generated podcast MP3 is present, listenable, and around eight
  minutes.
- Whether `render.json` records the selected TTS backend and any fallback.
- Whether `brief.pdf` renders cleanly and contains source links.

Record tech review notes in `research/tech-news/backlog.md`.
Record Poland/world review notes in `research/polska-swiat/backlog.md`.
Record LLM/AI jobs review notes in `research/llm-ai-jobs-wroclaw/backlog.md`.
Record mobile current-events review notes in
`research/aktualne-wydarzenia-mobile/backlog.md`.

## OpenClaw Decision Gate

Do not add OpenClaw as a runtime until the first three Codex-native reports
have been reviewed. If OpenClaw is tested later, start with the observer shape
documented in `integrations/openclaw/` and keep it read-only until explicitly
approved.
