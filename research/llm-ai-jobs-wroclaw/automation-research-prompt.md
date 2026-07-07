# Automation Prompt: LLM/AI Jobs Wroclaw Research

```text
$daily-research-agent

Uruchom research ofert pracy dla `research/llm-ai-jobs-wroclaw`. Pracuj po
polsku i uzywaj poprawnych polskich znakow w raportach. Najpierw przeczytaj:
`AGENTS.md`, `docs/architecture.md`,
`research/llm-ai-jobs-wroclaw/topic.md`,
`research/llm-ai-jobs-wroclaw/index.md`,
`research/llm-ai-jobs-wroclaw/backlog.md` oraz najnowszy raport z
`research/llm-ai-jobs-wroclaw/runs/`, jesli istnieje.

Cel: znajdz nowe i najciekawsze publiczne oferty pracy przy modelach LLM i
praktycznych systemach AI dla Wroclawia onsite/hybrid oraz pracy zdalnej z
Polski. Skupiaj sie na rolach hands-on: ML engineer, LLM engineer, NLP engineer,
applied scientist, RAG, AI agents, AI platform/infrastructure, MLOps dla
generative AI, ewaluacja modeli, inference, fine-tuning i bliskie role
inzynierskie. Nie raportuj ogolnych BI/data roles bez wyraznego watku AI/LLM,
czystego sales/marketingu ani ofert wymagajacych logowania do zrodla.

Sprawdz aktualne publiczne zrodla: publiczne job boardy i publiczne strony
karier firm. Korzystaj tylko ze zrodel dostepnych bez logowania. Preferuj
kanoniczne strony pracodawcow, gdy mozna je znalezc. Zapisz link dla kazdej
materialnej informacji i kazdej oferty.

Dedup: porownaj wyniki z sekcja "Seen Opportunities" w
`research/llm-ai-jobs-wroclaw/index.md`. Klucz to kanoniczny URL plus firma,
tytul i lokalizacja. Nie powielaj niezmienionych ofert. Pokaz poprzednio znana
oferte tylko wtedy, gdy zaszla materialna zmiana: wynagrodzenie, lokalizacja,
remote policy, firma, tytul, seniority, stack, deadline, status albo kanoniczny
URL.

Zapisz raport Markdown jako
`research/llm-ai-jobs-wroclaw/runs/YYYY-MM-DD-HHMM.md`, gdzie `HHMM` to czas
Europe/Warsaw uruchomienia. Raport ma zawierac:
- date i status: `Material update` albo `No material change`;
- zakres i zrodla sprawdzone w tej rundzie;
- executive summary;
- top nowe lub materialnie zmienione role, maksymalnie 8, z uzasadnieniem
  "dlaczego interesujace", dopasowaniem do LLM/AI, lokalizacja/remote,
  wynagrodzeniem jesli zrodlowane, niepewnoscia i linkami;
- zmiany od poprzedniej rundy;
- rekomendowane akcje;
- zrodla.

Jesli nie ma materialnych zmian, nadal utworz krotki raport ze statusem
`No material change`, lista sprawdzonych zrodel i jednym rzeczowym
podsumowaniem. Nie powtarzaj niezmienionych ofert.

Utworz tez strukturalny artefakt danych dla natywnego widoku Jobs w iOS:
`research/llm-ai-jobs-wroclaw/data/YYYY-MM-DD-HHMM-jobs.json`. JSON jest
obowiazkowy dla kazdego przebiegu i musi miec schema v1:
- `schemaVersion`: `1`;
- `status`, `runDate`, `runTime`, `executiveSummary`;
- `opportunities[]` z polami: `rank`, `title`, `company`, `location`,
  `workMode`, `compensation`, `seniority`, `fitSummary`, `whyInteresting`,
  `uncertainty`, `sourceURLs`, `tags`;
- `changes`, `risks`, `recommendedActions`;
- `checkedSources[]` z polami `title`, `url`, opcjonalnie `status`.

Kazda oferta w `opportunities[]` musi miec co najmniej jeden publiczny URL w
`sourceURLs`. Jesli pole jest niepewne, wpisz jawny tekst typu
`Brak publicznych widelek` albo `Niepotwierdzone w zrodle`, zamiast zostawiac
pusta wartosc. Po zapisaniu raportu Markdown wygeneruj JSON poleceniem:

`python3 research/llm-ai-jobs-wroclaw/tools/render_jobs_data.py research/llm-ai-jobs-wroclaw/runs/YYYY-MM-DD-HHMM.md research/llm-ai-jobs-wroclaw/data/YYYY-MM-DD-HHMM-jobs.json`

Nastepnie uruchom walidacje:

`python3 scripts/validate_jobs_data.py research/llm-ai-jobs-wroclaw/data/YYYY-MM-DD-HHMM-jobs.json`

Jesli JSON nie przejdzie walidacji, nie publikuj wyniku.

Zaktualizuj `research/llm-ai-jobs-wroclaw/index.md`: dodaj nowe kanoniczne
klucze do "Seen Opportunities", zaktualizuj `Last updated`, `Recent Reports`
oraz `Material changes` tylko przy istotnych zmianach. Zaktualizuj
`research/llm-ai-jobs-wroclaw/backlog.md`, gdy pojawia sie konkretny follow-up,
notatka przegladowa lub zamkniety element.

Wygeneruj profesjonalny mobile-first premium PDF z tego samego raportu jako
`research/llm-ai-jobs-wroclaw/pdfs/YYYY-MM-DD-HHMM-llm-ai-jobs-wroclaw.pdf`.
Uzyj bundlowanego runtime Codex, jesli jest dostepny przez
`codex_app.load_workspace_dependencies`; preferowany interpreter to zwrocona
sciezka Python. Uruchom:

`<bundled-python> research/llm-ai-jobs-wroclaw/tools/render_report_pdf.py <markdown-report> <pdf-output>`

Po wygenerowaniu PDF zweryfikuj go `pdfplumber` i `pdftoppm`, jesli narzedzia
sa dostepne. Sprawdz, czy ma format telefonu 390 x 844 pt, tekst nie jest
pusty, polskie znaki sa czytelne, linki zrodel sa widoczne, karty ofert nie
uciekaja poza marginesy, a pierwsza strona renderuje sie bez bledow i bez
potrzeby zoomu w aplikacji Pavbot.
PDF jest obowiazkowym artefaktem tej automatyzacji: jesli render PDF nie
powstanie albo weryfikacja wykryje pusty/nieczytelny plik, nie publikuj
wynikow i zglos blad przebiegu.

Po zapisaniu raportu, indeksu, backlogu, JSON i PDF opublikuj wyniki dla
aplikacji iOS i webhooka notyfikacji push. Skrypt uruchamia
`python3 scripts/generate_pavbot_manifest.py`, odswieza
`public/pavbot-manifest.json`, commituje tylko dozwolone sciezki i robi push na
`origin/main`. Skrypt sam wyprowadza `PAVBOT_MANIFEST_URL` z override
srodowiskowego, `PAVBOT_RAW_BASE_URL`, istniejacego `rawBaseUrl` w manifescie
albo GitHub `origin`; ustaw zmienna recznie tylko dla niestandardowego URL.
Rozwiazany URL musi odpowiadac iOS `Settings -> Manifest URL`. Nastepnie
uruchom:
`scripts/pavbot_commit_and_push_outputs.sh --isolated research/llm-ai-jobs-wroclaw`.

Po publishu wykonaj obowiazkowy etap `post-publish verification`. Uzyj tego
samego `RUN_STAMP=YYYY-MM-DD-HHMM`, ktorego uzyles do nazw plikow, a nastepnie
uruchom:

`RUN_PATH="research/llm-ai-jobs-wroclaw/runs/${RUN_STAMP}.md"`

`DATA_PATH="research/llm-ai-jobs-wroclaw/data/${RUN_STAMP}-jobs.json"`

`PDF_PATH="research/llm-ai-jobs-wroclaw/pdfs/${RUN_STAMP}-llm-ai-jobs-wroclaw.pdf"`

`git fetch origin`

`git show origin/main:public/pavbot-manifest.json | grep -F "$RUN_PATH"`

`git show origin/main:public/pavbot-manifest.json | grep -F "$DATA_PATH"`

`git show origin/main:public/pavbot-manifest.json | grep -F "$PDF_PATH"`

`git show "origin/main:$RUN_PATH" >/dev/null`

`git show "origin/main:$DATA_PATH" >/dev/null`

`git show "origin/main:$PDF_PATH" >/dev/null`

To jest twardy warunek sukcesu. Jesli `origin/main:public/pavbot-manifest.json`
nie zawiera biezacego package key albo ktorykolwiek z trzech artefaktow nie
jest widoczny na `origin/main`, traktuj przebieg jako nieudany i nie raportuj
go jako zakonczonego sukcesem.

Uzyj risk gate z `docs/architecture.md`. W ramach tej automatyzacji wolno
zmieniac tylko pliki w `research/llm-ai-jobs-wroclaw/`. Finalny krok publikacji
moze commitowac tylko `research/llm-ai-jobs-wroclaw/runs/`,
`research/llm-ai-jobs-wroclaw/pdfs/`,
`research/llm-ai-jobs-wroclaw/data/`,
`research/llm-ai-jobs-wroclaw/podcasts/`,
`research/llm-ai-jobs-wroclaw/index.md`,
`research/llm-ai-jobs-wroclaw/backlog.md` oraz
`public/pavbot-manifest.json`. Jesli rekomendowana akcja wymagalaby zmiany
automatyzacji, instrukcji repo, skilli, hookow, MCP, zaleznosci lub plikow poza
aktywnym tematem, utworz propozycje w `research/llm-ai-jobs-wroclaw/proposals/`
zamiast stosowac zmiane.
```
