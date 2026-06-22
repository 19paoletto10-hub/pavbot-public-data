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

Zaktualizuj `research/llm-ai-jobs-wroclaw/index.md`: dodaj nowe kanoniczne
klucze do "Seen Opportunities", zaktualizuj `Last updated`, `Recent Reports`
oraz `Material changes` tylko przy istotnych zmianach. Zaktualizuj
`research/llm-ai-jobs-wroclaw/backlog.md`, gdy pojawia sie konkretny follow-up,
notatka przegladowa lub zamkniety element.

Po zapisaniu artefaktow odswiez publiczny manifest dla aplikacji iOS:
`python3 scripts/generate_pavbot_manifest.py`.

Wygeneruj profesjonalny PDF z tego samego raportu jako
`research/llm-ai-jobs-wroclaw/pdfs/YYYY-MM-DD-HHMM-llm-ai-jobs-wroclaw.pdf`.
Uzyj bundlowanego runtime Codex, jesli jest dostepny przez
`codex_app.load_workspace_dependencies`; preferowany interpreter to zwrocona
sciezka Python. Uruchom:

`<bundled-python> research/llm-ai-jobs-wroclaw/tools/render_report_pdf.py <markdown-report> <pdf-output>`

Po wygenerowaniu PDF zweryfikuj go `pdfplumber` lub `pdftoppm`, jesli narzedzia
sa dostepne. Sprawdz, czy tekst nie jest pusty, polskie znaki sa czytelne,
linki zrodel sa widoczne, a pierwsza strona renderuje sie bez bledow.

Uzyj risk gate z `docs/architecture.md`. W ramach tej automatyzacji wolno
zmieniac tylko pliki w `research/llm-ai-jobs-wroclaw/`. Jesli rekomendowana
akcja wymagalaby zmiany automatyzacji, instrukcji repo, skilli, hookow, MCP,
zaleznosci lub plikow poza aktywnym tematem, utworz propozycje w
`research/llm-ai-jobs-wroclaw/proposals/` zamiast stosowac zmiane.
```
