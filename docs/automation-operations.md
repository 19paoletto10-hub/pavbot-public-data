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
  `research/llm-ai-jobs-wroclaw` with timestamped Markdown reports and PDFs.
  Repository manifest ID: `pavbot-llm-ai-jobs-wroclaw-research`.
- `Pavbot Aktualne Wydarzenia Mobile 10:15` runs daily at 10:15 Europe/Warsaw
  and updates `research/aktualne-wydarzenia-mobile` with one timestamped
  package: `runs/YYYY-MM-DD-HHMM.md`, `pdfs/YYYY-MM-DD-HHMM-mobile-brief.pdf`,
  `podcasts/YYYY-MM-DD-HHMM/`, female Piper MP3, male XTTS MP3, script,
  sources, and variant metadata. ID: `pavbot-aktualne-wydarzenia-mobile-10-15`.

## Publishing Contract

Every active automation must finish with the shared publication script:

```bash
export PAVBOT_MANIFEST_URL="https://raw.githubusercontent.com/<owner>/<repo>/<branch>/public/pavbot-manifest.json"
scripts/pavbot_commit_and_push_outputs.sh --isolated research/<topic>
```

The isolated script creates a temporary clean worktree from `origin/main`,
copies only generated outputs from the active topic, refreshes
`public/pavbot-manifest.json`, commits those files, and pushes to
`origin/main`. It requires a working `origin`, `PAVBOT_MANIFEST_URL`, and push
credentials for `main`. Do not push generated automation files separately from
the refreshed manifest. The GitHub webhook for live iOS notifications fires
only after this push succeeds.

Automation output commits may include only `runs/`, `pdfs/`, `podcasts/`,
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
