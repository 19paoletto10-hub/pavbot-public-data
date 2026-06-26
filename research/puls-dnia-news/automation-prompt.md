# Automation Prompt: Pavbot Puls Dnia 3h

```text
$daily-research-agent

Uruchom workflow `Pavbot Puls Dnia 3h` dla `research/puls-dnia-news`.
Pracuj po polsku, używaj poprawnych polskich znaków i zachowuj linki źródeł.

Najpierw przeczytaj `AGENTS.md`, `docs/architecture.md`,
`research/puls-dnia-news/topic.md`, `research/puls-dnia-news/index.md`,
`research/puls-dnia-news/backlog.md` oraz najnowszy raport z
`research/puls-dnia-news/runs/`, jeśli istnieje.

Ustal jeden wspólny timestamp w strefie Europe/Warsaw:

RUN_STAMP=$(TZ=Europe/Warsaw date +%Y-%m-%d-%H%M)
RUN_DATE=${RUN_STAMP:0:10}

Sprawdź aktualne publiczne źródła internetowe: TVN24, BBC i CNN jako źródła
wykrywania tematów. Najważniejsze fakty potwierdzaj źródłami oficjalnymi lub
pierwotnymi, jeśli są dostępne. Obejmij sekcje: `Polska`, `Świat`, `Polityka`,
`Bezpieczeństwo`, `Gospodarka`, `Technologia`, `Alerty`.

Zapisz raport Markdown jako:

research/puls-dnia-news/runs/YYYY-MM-DD-HHMM.md

Raport ma zawierać: datę i godzinę, status, zakres źródeł, krótkie
podsumowanie, listę wybranych tematów, fakty oddzielone od interpretacji,
niepewności, rekomendowane obserwacje i linki źródeł. Jeśli temat nie ma
materialnego potwierdzenia, opisz go jako niejednoznaczny albo pomiń.

Następnie utwórz strukturalny JSON:

research/puls-dnia-news/data/YYYY-MM-DD-HHMM-pulse-news.json

Schema v1:
- `schemaVersion`: 1
- `runDate`: `YYYY-MM-DD`
- `runTime`: `HH:MM`
- `status`
- `headline`
- `summary`
- `items`
- `checkedSources`

Każdy element `items[]` ma mieć:
- `id`
- `section`
- `title`
- `lead`
- `whatHappened`
- `keyFacts`
- `reactions`
- `whyItMatters`
- `context`
- `watchNext`
- `sources`
- `tags`
- `priority`

Wymagania jakości:
- minimum 12 newsów;
- parzysta liczba newsów;
- co najmniej dwa tematy krajowe i dwa światowe;
- każda karta ma mieć źródła;
- opisy mają być gotowe do natywnego interfejsu iOS, bez Markdown link syntax w
  polach opisowych;
- `lead` ma być krótki i czytelny na kafelku;
- szczegóły analityczne umieść w `whatHappened`, `keyFacts`, `reactions`,
  `whyItMatters`, `context`, `watchNext`.

Zweryfikuj JSON:

python3 scripts/validate_pulse_news_data.py research/puls-dnia-news/data/YYYY-MM-DD-HHMM-pulse-news.json

Jeśli walidacja nie przejdzie, popraw JSON i raport. Nie publikuj niepoprawnych
danych.

Na końcu opublikuj wynik dla aplikacji iOS i webhooka powiadomień:

scripts/pavbot_commit_and_push_outputs.sh --isolated research/puls-dnia-news

Skrypt ma odświeżyć `public/pavbot-manifest.json`, commitować tylko dozwolone
pliki aktywnego topicu oraz manifest, a następnie zrobić push na `origin/main`.
Po publikacji sprawdź, że manifest zawiera najnowszy plik
`research/puls-dnia-news/data/*-pulse-news.json` jako `type: "pulseNewsData"`.
Jeśli manifest nie zawiera najnowszych danych, zgłoś błąd runu zamiast
oznaczać automatyzację jako udaną.
Nie commituj zmian developerskich, promptów, skilli, kodu iOS ani backendu jako
wyników tej automatyzacji.
```
