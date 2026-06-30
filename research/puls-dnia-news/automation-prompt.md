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

To jest heartbeat slotowy dla godzin 06:00, 09:00, 12:00, 15:00, 18:00 i 21:00
Europe/Warsaw. Każde uruchomienie ma obowiązkowo sprawdzić źródła w poszukiwaniu
nowych materiałów względem ostatniego opublikowanego `pulseNewsData`.

Zanim napiszesz nowe outputy:

- uruchom `git fetch origin`;
- odczytaj z `origin/main:public/pavbot-manifest.json` najnowszą opublikowaną
  ścieżkę `research/puls-dnia-news/data/*-pulse-news.json`;
- traktuj tę zdalnie opublikowaną ścieżkę jako baseline porównania dla nowego
  checku źródeł.

Sprawdź aktualne publiczne źródła internetowe: TVN24, BBC i CNN jako źródła
wykrywania tematów. Najważniejsze fakty potwierdzaj źródłami oficjalnymi lub
pierwotnymi, jeśli są dostępne. Obejmij sekcje: `Polska`, `Świat`, `Polityka`,
`Bezpieczeństwo`, `Gospodarka`, `Technologia`, `Alerty`.

Jeśli znajdziesz nowe materialne artykuły względem ostatniego opublikowanego
runu, MUSISZ utworzyć nowy `runs/YYYY-MM-DD-HHMM.md`, nowy
`data/YYYY-MM-DD-HHMM-pulse-news.json`, odświeżyć manifest i opublikować wynik
na `origin/main` w tym samym przebiegu. Nie wolno kończyć runu na lokalnym
zapisie plików.

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

`python3 scripts/pavbot_publication_contract.py prepare research/puls-dnia-news`

`python3 scripts/pavbot_publication_contract.py verify-local research/puls-dnia-news`

To jest pipeline `prepare -> validate -> manifest -> push -> verify-remote`.
W tym temacie `prepare` nie generuje brakujących artefaktów, tylko egzekwuje
kontrakt `run + pulseNewsData`.

`scripts/pavbot_commit_and_push_outputs.sh --isolated research/puls-dnia-news`

Skrypt ma odświeżyć `public/pavbot-manifest.json`, commitować tylko dozwolone
pliki aktywnego topicu oraz manifest, a następnie zrobić push na `origin/main`.
Po publikacji:

- uruchom `python3 scripts/pavbot_publication_contract.py verify-remote research/puls-dnia-news --ref origin/main`;
- sprawdź publiczny raw manifest URL używany przez iOS i notifier
  (`PAVBOT_MANIFEST_URL` albo `rawBaseUrl` z manifestu) i potwierdź, że ten
  publiczny HTTP odczyt widzi bieżący `pulseNewsData`;
- sprawdź publiczny raw URL bieżącego
  `research/puls-dnia-news/data/YYYY-MM-DD-HHMM-pulse-news.json` z manifestu i
  potwierdź, że HTTP zwraca poprawny JSON z tym samym `runDate`, `runTime` oraz
  niepustym `items`;
- jeśli znalazłeś nowe artykuły, a manifest na `origin/main` nadal pokazuje
  starszy stamp niż bieżący run, zgłoś błąd runu zamiast oznaczać automatyzację
  jako udaną.

Nie zostawiaj stanu, w którym lokalnie istnieje nowszy `pulse-news.json` niż
ten widoczny w zdalnym manifeście. Dla powiadomień push warunkiem gotowości jest
publiczna dostępność raw manifestu i raw JSON-a, nie tylko obecność blobów w
`origin/main`.

Nie commituj zmian developerskich, promptów, skilli, kodu iOS ani backendu jako
wyników tej automatyzacji.
```
