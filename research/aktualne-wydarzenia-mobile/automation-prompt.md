# Automation Prompt: Pavbot Aktualne Wydarzenia Mobile 10:15 / 19:35

```text
$daily-research-agent

Uruchom kompletny workflow dla bieżącego porannego albo wieczornego wydania
`research/aktualne-wydarzenia-mobile`. Pracuj po polsku i używaj poprawnych
polskich znaków. Ta sama procedura obowiązuje dla heartbeatów 10:15 i 19:35
Europe/Warsaw.

Najpierw przeczytaj `AGENTS.md`, `docs/architecture.md`,
`research/aktualne-wydarzenia-mobile/topic.md`,
`research/aktualne-wydarzenia-mobile/index.md`,
`research/aktualne-wydarzenia-mobile/backlog.md` oraz najnowszy raport z
`research/aktualne-wydarzenia-mobile/runs/`, jeśli istnieje.

Na początku runu ustal jeden wspólny czas utworzenia w strefie Europe/Warsaw i
używaj go we wszystkich nazwach plików tego przebiegu:
`RUN_STAMP=$(TZ=Europe/Warsaw date +%Y-%m-%d-%H%M)` oraz
`RUN_DATE=${RUN_STAMP:0:10}`. W przykładach poniżej `YYYY-MM-DD-HHMM` oznacza
wartość `RUN_STAMP`, a `YYYY-MM-DD` oznacza `RUN_DATE`. Ten sam stamp musi
zostać przekazany do publikacji jako twarda bramka sukcesu:
`export PAVBOT_EXPECTED_MOBILE_NEWS_STAMP="$RUN_STAMP"`.
Jeśli bieżący przebieg jest poranny, nie nadpisuj ani nie usuwaj wieczornego
pakietu z tego samego dnia. Jeśli przebieg jest wieczorny, traktuj poranne
wydanie jako kontekst i zachowaj oba pakiety w manifeście.

Sprawdź aktualne publiczne źródła internetowe dotyczące najważniejszych
wydarzeń z Polski i świata: polityki, bezpieczeństwa, dyplomacji, decyzji
rządów, społeczeństwa, gospodarki publicznej, konfliktów i ważnych zdarzeń
międzynarodowych. Preferuj źródła pierwotne i oficjalne komunikaty, a redakcje
newsowe traktuj jako potwierdzenie lub sygnał. Korzystaj m.in. z KPRM,
Prezydent RP, Sejm, Senat, MON, MSZ, RCB, IMGW, TVN24, WP, Onet, Interia,
RMF24, Polsat News, Business Insider Polska, PAP jeśli publicznie dostępne,
BBC, Reuters/AP przez publicznie dostępne strony, The Guardian, Politico,
Euronews, Komisja Europejska, Consilium, NATO i ONZ.

Zapisz raport Markdown jako
`research/aktualne-wydarzenia-mobile/runs/YYYY-MM-DD-HHMM.md`. Raport ma zawierać:
datę, godzinę utworzenia, status `Material update` albo `No material change`, zakres sprawdzonych
źródeł, krótkie podsumowanie, sekcję `Nowe fakty`, sekcję `Interpretacja`,
ryzyka/niepewności, rekomendowane akcje i źródła. Zachowaj linki przy każdym
materialnym twierdzeniu. Oddziel fakty od interpretacji.

Dodatkowo dodaj blok `## Gazeta` do tego samego raportu Markdown. Blok ma mieć
sekcje `### Ogólne`, `### Polska`, `### Polityka`, `### Sprawy zagraniczne` i
`### Technologia`. Każda sekcja musi zaczynać się od pola
`Wprowadzenie: ...`, które ogólnie opisuje aktualny stan informacji w tej
sekcji i nie może powtarzać leadu żadnego pojedynczego artykułu. Po
`Wprowadzenie` każda sekcja musi zawierać minimum dwa artykuły w formacie
`#### Tytuł`, `Lead: ...`, `Fakty:` z listą punktów i linkami źródeł,
`Analiza: ...` oraz `Dlaczego to ważne: ...`. Jeśli dana sekcja nie ma drugiego
nowego faktu o wysokiej wadze publicznej, wpisz drugi artykuł
`Brak materialnej zmiany` lub `Co sprawdzono bez przełomu`, ale nadal podaj
sprawdzone źródła, analizę i wyjaśnienie znaczenia zamiast wypełniaczy.

Następnie przygotuj folder podcastu:
`research/aktualne-wydarzenia-mobile/podcasts/YYYY-MM-DD-HHMM/`. Utwórz `draft.md`,
zweryfikuj twierdzenia wobec źródeł i zapisz finalny `script.md`. Scenariusz ma
być po polsku, bez surowych URL-i, gotowy pod podcastowy TTS z automatycznie
wykrywanym językiem. Dodaj lekki, inteligentny humor tylko tam, gdzie nie
umniejsza powagi wydarzeń. Liczby, daty, skróty i nazwiska zapisuj naturalnie
dla lektora. Utwórz `sources.md` z sekcjami:
`## Źródła użyte w scenariuszu`,
`## Źródła sprawdzone, ale niewykorzystane`,
`## Źródła niedostępne lub niejednoznaczne`.

Uruchom lint redakcyjny:
`bash .agents/scripts/podcast/editorial_lint.sh research/aktualne-wydarzenia-mobile/podcasts/YYYY-MM-DD-HHMM/script.md research/aktualne-wydarzenia-mobile/podcasts/YYYY-MM-DD-HHMM/sources.md`.

Wygeneruj PDF pod ekrany mobilne:
`~/.cache/pavbot/venvs/pdf/bin/python research/aktualne-wydarzenia-mobile/tools/render_mobile_brief_pdf.py research/aktualne-wydarzenia-mobile/runs/YYYY-MM-DD-HHMM.md research/aktualne-wydarzenia-mobile/podcasts/YYYY-MM-DD-HHMM research/aktualne-wydarzenia-mobile/pdfs/YYYY-MM-DD-HHMM-mobile-brief.pdf --topic aktualne-wydarzenia-mobile`.

Wygeneruj szczegółowy PDF w stylu mobilnej gazety:
`~/.cache/pavbot/venvs/pdf/bin/python research/aktualne-wydarzenia-mobile/tools/render_mobile_newspaper_pdf.py research/aktualne-wydarzenia-mobile/runs/YYYY-MM-DD-HHMM.md research/aktualne-wydarzenia-mobile/pdfs/YYYY-MM-DD-HHMM-newspaper.pdf --topic aktualne-wydarzenia-mobile`.
Oba PDF-y mają wyglądać premium i być wygodne do czytania na telefonie:
390 x 844 pt, czytelne bez zoomu w aplikacji Pavbot, z wyraźnymi kartami,
widocznymi linkami źródeł i dopracowanymi stopkami. Po renderze wyrenderuj
strony do PNG i sprawdź wizualnie spacing, polskie znaki oraz brak ucięć lub
nakładania tekstu.

Wygeneruj dwa warianty TTS:
`bash research/aktualne-wydarzenia-mobile/tools/render_two_tts_variants.sh research/aktualne-wydarzenia-mobile/podcasts/YYYY-MM-DD-HHMM/script.md research/aktualne-wydarzenia-mobile/podcasts/YYYY-MM-DD-HHMM`.

Warianty audio mają być zapisane jako:
- `research/aktualne-wydarzenia-mobile/podcasts/YYYY-MM-DD-HHMM/audio/female-piper/podcast.mp3`
- `research/aktualne-wydarzenia-mobile/podcasts/YYYY-MM-DD-HHMM/audio/male-xtts/podcast.mp3`

Zapisz zbiorcze metadane w
`research/aktualne-wydarzenia-mobile/podcasts/YYYY-MM-DD-HHMM/tts_variants.json`.
Jeśli jeden wariant TTS zawiedzie, nie twórz fałszywego MP3; zachowaj raport,
PDF, skrypt, źródła i zapisz błąd w metadanych oraz backlogu.

Dopiero po renderze TTS wygeneruj strukturalne dane dla natywnego widoku
`Research -> Aktualne`, ponieważ JSON musi zawierać `audioArtifacts` wskazujące
istniejące pliki MP3:
`python3 scripts/render_mobile_news_data.py research/aktualne-wydarzenia-mobile/runs/YYYY-MM-DD-HHMM.md research/aktualne-wydarzenia-mobile/data/YYYY-MM-DD-HHMM-mobile-news.json`.
Następnie uruchom walidację:
`python3 scripts/validate_mobile_news_data.py research/aktualne-wydarzenia-mobile/data/YYYY-MM-DD-HHMM-mobile-news.json`.
Jeśli walidacja zgłosi brak pięciu sekcji, mniej niż dwa artykuły w sekcji,
brak `audioArtifacts`, pustą listę audio albo powielony opis sekcji i lead
artykułu, popraw raport Markdown lub audio workflow i wygeneruj JSON ponownie
przed publikacją.

Artefakty redakcyjne i diagnostyczne, czyli raport Markdown, `draft.md`,
`sources.md` i `tts_variants.json`, nadal mają powstawać lokalnie na potrzeby
weryfikacji, renderu PDF i debugowania. Finalny `script.md` jest również
publicznym tekstowym źródłem dla lokalnego TTS w aplikacji iOS. Publiczna
publikacja dla aplikacji iOS przez CloudKit briefing i manifest danych ma obejmować:
- `research/aktualne-wydarzenia-mobile/data/YYYY-MM-DD-HHMM-mobile-news.json`
- `research/aktualne-wydarzenia-mobile/pdfs/YYYY-MM-DD-HHMM-mobile-brief.pdf`
- `research/aktualne-wydarzenia-mobile/podcasts/YYYY-MM-DD-HHMM/script.md`
- `research/aktualne-wydarzenia-mobile/podcasts/YYYY-MM-DD-HHMM/audio/*/podcast.mp3`

Publikuj tylko te warianty audio, dla których istnieje poprawnie wyrenderowany
`podcast.mp3`. Nie publikuj placeholderów, `tts_variants.json`, `render.json`,
`sources.md`, raportów `runs/` ani dodatkowych PDF-ów.

Po zapisaniu artefaktów opublikuj wyniki dla aplikacji iOS przez metadane
briefingu w CloudKit oraz publiczny manifest danych. Skrypt uruchamia
`python3 scripts/generate_pavbot_manifest.py`, odświeża
`public/pavbot-manifest.json`, commituje tylko dozwolone ścieżki i robi push na
`origin/main`.
Skrypt sam wyprowadza `PAVBOT_MANIFEST_URL` z override środowiskowego,
`PAVBOT_RAW_BASE_URL`, istniejącego `rawBaseUrl` w manifeście albo GitHub
`origin`; ustaw zmienną ręcznie tylko dla niestandardowego URL. Rozwiązany URL
musi odpowiadać iOS `Settings -> Manifest URL`. Przed publikacją upewnij się,
że `PAVBOT_EXPECTED_MOBILE_NEWS_STAMP="$RUN_STAMP"` wskazuje bieżący przebieg;
wspólny skrypt musi odmówić sukcesu, jeśli nie istnieje dokładnie
`research/aktualne-wydarzenia-mobile/data/${RUN_STAMP}-mobile-news.json` albo
manifest nie promuje go jako `mobileNewsData`. Wspólny skrypt odświeża token
użytkownika CloudKit dla `cktool` przed produkcyjną publikacją komendą
`xcrun cktool save-token --type user --method keychain --force`. Następnie
uruchom:
`scripts/pavbot_commit_and_push_outputs.sh --isolated research/aktualne-wydarzenia-mobile`.
Po publikacji sprawdź publiczny manifest i raw URL dla bieżącego stampu. Sukces
porannego lub wieczornego wydania oznacza, że `origin/main` zawiera pasujące
artefakty `mobileNewsData`, `mobile-brief.pdf`, `script.md` i każdy istniejący
`audio/*/podcast.mp3` dla tego samego `RUN_STAMP`.

Użyj risk gate z `docs/architecture.md`. W ramach tej automatyzacji wolno
zmieniać tylko pliki w `research/aktualne-wydarzenia-mobile/` oraz manifest
publiczny generowany ze źródeł. Finalny krok publikacji może commitować tylko
`research/aktualne-wydarzenia-mobile/data/`,
`research/aktualne-wydarzenia-mobile/pdfs/`,
`research/aktualne-wydarzenia-mobile/podcasts/*/script.md`,
`research/aktualne-wydarzenia-mobile/podcasts/*/audio/*/podcast.mp3` oraz
`public/pavbot-manifest.json`. Jeśli rekomendowana akcja wymaga zmiany
automatyzacji, instrukcji repo, skilli, hooków, MCP, zależności albo plików poza
aktywnym tematem, utwórz propozycję w
`research/aktualne-wydarzenia-mobile/proposals/` zamiast stosować zmianę.
```
