# Automation Prompt: Pavbot Polska Świat Research 08:30

```text
$daily-research-agent

Uruchom codzienny research wiadomości dla `research/polska-swiat`.
Pracuj po polsku i używaj poprawnych polskich znaków. Przeczytaj `AGENTS.md`,
`docs/architecture.md`, `research/polska-swiat/topic.md`,
`research/polska-swiat/index.md`, `research/polska-swiat/backlog.md` i
najnowszy raport dzienny, jeśli istnieje.

Sprawdź aktualne publiczne źródła internetowe dotyczące Polski i świata:
polityka, rząd, parlament, bezpieczeństwo, gospodarka publiczna, społeczeństwo,
dyplomacja, konflikty, wybory, decyzje rządów i ważne wydarzenia. Korzystaj z
publicznych serwisów informacyjnych i źródeł pierwotnych, m.in. TVN24, WP,
Onet, Interia, RMF24, Polsat News, Business Insider Polska, PAP jeśli publicznie
dostępne, BBC, Reuters/AP przez publicznie dostępne strony, The Guardian,
Politico, Euronews i oficjalnych komunikatów instytucji.

Zapisz dzisiejszy raport do `research/polska-swiat/runs/YYYY-MM-DD.md`. Raport
ma zawierać linki do wszystkich materialnych źródeł, rozdział "Nowe fakty" oraz
sekcję "Tematy do podcastu" z 5-8 kandydatami. Przy każdym kandydacie podaj:
tytuł, dlaczego to ważne, główne źródła i priorytet.

Dodatkowo utwórz strukturalny JSON dla natywnego czytnika iOS:
`research/polska-swiat/data/YYYY-MM-DD-research.json`. Wygeneruj go komendą:
`python3 scripts/render_research_data.py research/polska-swiat/runs/YYYY-MM-DD.md`
i zwaliduj:
`python3 scripts/validate_research_data.py research/polska-swiat/data/YYYY-MM-DD-research.json`.
JSON jest obowiązkowym artefaktem tej automatyzacji. Musi zawierać po polsku:
lead, punkty podsumowania, artykuły z polami `whatHappened`, `whyItMatters`,
`deeperAnalysis`, `contextPoints`, źródła i tagi. Jeśli JSON nie powstanie albo
walidator zwróci błąd, nie publikuj wyników i zgłoś błąd przebiegu.

Dodatkowo wygeneruj estetyczny, profesjonalny PDF mobile-first z tym samym
researchem do `research/polska-swiat/pdfs/YYYY-MM-DD-polska-swiat.pdf`,
używając `scripts/render_research_pdf.py`. PDF ma być wygodny do czytania w
aplikacji Pavbot na iPhonie: większy tekst, krótkie linie, wyraźne wyróżnienie
"Najważniejsze", czytelne bloki "Dlaczego to ważne" i podkreślone linki
źródeł. Po wygenerowaniu wyrenderuj strony PDF do PNG i sprawdź wizualnie brak
ucięć tekstu, polskie znaki, mobilne karty tematów oraz stopki.
PDF jest obowiązkowym artefaktem tej automatyzacji: jeśli render PDF nie
powstanie albo weryfikacja wykryje pusty/nieczytelny plik, nie publikuj
wyników i zgłoś błąd przebiegu.

Zaktualizuj `research/polska-swiat/index.md`, gdy zmienia się obecny stan
wiedzy. Zaktualizuj `research/polska-swiat/backlog.md`, gdy pojawiają się
konkretne follow-upy, notatki przeglądowe, pytania albo rozwiązane elementy.

Po zapisaniu artefaktów opublikuj wyniki dla aplikacji iOS i webhooka
notyfikacji push. Skrypt uruchamia `python3 scripts/generate_pavbot_manifest.py`,
odświeża `public/pavbot-manifest.json`, commituje tylko dozwolone ścieżki i robi
push na `origin/main`.
Skrypt sam wyprowadza `PAVBOT_MANIFEST_URL` z override środowiskowego,
`PAVBOT_RAW_BASE_URL`, istniejącego `rawBaseUrl` w manifeście albo GitHub
`origin`; ustaw zmienną ręcznie tylko dla niestandardowego URL. Rozwiązany URL
musi odpowiadać iOS `Settings -> Manifest URL`. Następnie uruchom:
`scripts/pavbot_commit_and_push_outputs.sh --isolated research/polska-swiat`.

Użyj risk gate z `docs/architecture.md`. Jeśli rekomendowana akcja zmieniałaby
automatyzacje, instrukcje repo, skille, hooki, MCP, zależności albo pliki poza
aktywnym tematem, utwórz propozycję w `research/polska-swiat/proposals/`
zamiast stosować zmianę. Finalny krok publikacji może commitować tylko
`research/polska-swiat/runs/`, `research/polska-swiat/pdfs/`,
`research/polska-swiat/data/`,
`research/polska-swiat/podcasts/`, `research/polska-swiat/index.md`,
`research/polska-swiat/backlog.md` oraz `public/pavbot-manifest.json`.

Jeśli nie ma materialnych zmian, nadal utwórz krótki raport z `Status: No
material change`, sprawdzonymi źródłami i jednym zdaniem podsumowania.
```
