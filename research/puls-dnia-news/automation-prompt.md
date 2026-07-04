# Automation Prompt: Pavbot Puls Dnia 3h

```text
$daily-research-agent

Uruchom workflow `Pavbot Puls Dnia 3h` dla `research/puls-dnia-news`.
Pracuj po polsku, używaj poprawnych polskich znaków i zachowuj linki źródeł.

Najpierw przeczytaj `AGENTS.md`, `docs/architecture.md`,
`research/puls-dnia-news/topic.md`, `research/puls-dnia-news/index.md`,
`research/puls-dnia-news/backlog.md` oraz najnowszy raport z
`research/puls-dnia-news/runs/`, jeśli istnieje.

Następnie:

1. Ustal wspólny timestamp `Europe/Warsaw` w formacie `YYYY-MM-DD-HHMM`.
2. Uruchom `git fetch origin` i odczytaj z `origin/main:public/pavbot-manifest.json`
   najnowszą opublikowaną ścieżkę `research/puls-dnia-news/data/*-pulse-news.json`.
   To jest baseline porównania.
3. Sprawdź bieżące źródła TVN24, BBC i CNN. Najważniejsze fakty potwierdzaj
   źródłami oficjalnymi lub pierwotnymi, jeśli są dostępne.
4. Jeśli są nowe materialne tematy względem ostatniego opublikowanego
   `pulseNewsData`, utwórz dokładnie dwa pliki:
   - `research/puls-dnia-news/runs/YYYY-MM-DD-HHMM.md`
   - `research/puls-dnia-news/data/YYYY-MM-DD-HHMM-pulse-news.json`

Nie twórz PDF, obrazów ani innych dodatkowych artefaktów. W tym topiku jedyne
outputy potrzebne aplikacji iOS to raport Markdown oraz `pulseNewsData` JSON.

Raport Markdown ma być krótki i rzeczowy: data i godzina, status, zakres
źródeł, podsumowanie, nowe fakty, zmiany względem baseline, ryzyka,
rekomendowane obserwacje i linki źródeł.

JSON ma być profesjonalnie opisany, gotowy do natywnego UI iOS i zgodny ze
schemą v1:
- pola główne: `schemaVersion`, `topic`, `runDate`, `runTime`, `status`,
  `headline`, `summary`, `items`, `checkedSources`
- każde `items[]`: `id`, `section`, `title`, `lead`, `whatHappened`,
  `keyFacts`, `reactions`, `whyItMatters`, `context`, `watchNext`, `sources`,
  `tags`, `priority`

Wymagania jakości JSON:
- minimum 12 newsów i parzysta liczba elementów;
- co najmniej 2 tematy `Polska` lub `Polityka` i co najmniej 2 tematy `Świat`;
- każda karta ma mieć źródła;
- `lead` ma być krótki, klarowny i dobry na kafelek;
- pola opisowe mają być profesjonalne, konkretne i bez składni Markdown linków;
- analitykę umieszczaj w `whatHappened`, `keyFacts`, `reactions`,
  `whyItMatters`, `context`, `watchNext`.

Zweryfikuj JSON:
`python3 scripts/validate_pulse_news_data.py research/puls-dnia-news/data/YYYY-MM-DD-HHMM-pulse-news.json`

Jeśli walidacja nie przejdzie, popraw pliki. Nie publikuj niepoprawnych danych.

Na końcu opublikuj:
- `python3 scripts/pavbot_publication_contract.py prepare research/puls-dnia-news`
- `python3 scripts/pavbot_publication_contract.py verify-local research/puls-dnia-news`
- `scripts/pavbot_commit_and_push_outputs.sh --isolated research/puls-dnia-news`
- `python3 scripts/pavbot_publication_contract.py verify-remote research/puls-dnia-news --ref origin/main`

Potwierdź też przez publiczny raw manifest i publiczny raw JSON, że iOS widzi
najnowszy `pulseNewsData`. Nie zostawiaj stanu, w którym lokalnie istnieje
nowszy `pulse-news.json` niż ten widoczny w zdalnym manifeście.
```
