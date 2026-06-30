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
`python3 scripts/render_research_data.py research/polska-swiat/runs/YYYY-MM-DD.md --require-app-articles`
i zwaliduj:
`python3 scripts/validate_research_data.py research/polska-swiat/data/YYYY-MM-DD-research.json`.
JSON jest obowiązkowym artefaktem tej automatyzacji. Musi zawierać po polsku:
lead, punkty podsumowania, artykuły z polami `whatHappened`, `whyItMatters`,
`deeperAnalysis`, `contextPoints`, źródła i tagi. Jeśli JSON nie powstanie albo
walidator zwróci błąd, nie publikuj wyników i zgłoś błąd przebiegu. Błąd
`--require-app-articles` oznacza twardy stop: popraw raport i kompletność
sekcji aplikacyjnej przed ponownym renderem.
Publikacja nie jest kompletna, jeśli bieżący JSON
`research/polska-swiat/data/YYYY-MM-DD-research.json` nie jest wypchnięty na
`origin/main` i nie występuje w zdalnym `public/pavbot-manifest.json` jako
artefakt `researchData`; bez tego aplikacja iOS nie zobaczy zmian.

Przed wygenerowaniem JSON przygotuj w raporcie sekcję `## Artykuły do aplikacji`.
Dla każdego artykułu wykonaj dodatkowe, krótkie przeszukanie internetu po
kontekście tematu, najlepiej w źródłach instytucjonalnych, pierwotnych albo
renomowanych mediach public-news. Nie powtarzaj w `Pełny opis` tekstu ze
`Standfirst` ani `Co się stało`. Użyj formatu:

```text
### Tytuł artykułu
Sekcja: Polska | Polityka | Świat | Bezpieczeństwo | Gospodarka | Pogoda
Priorytet: High | Medium | Low
Tagi: tag1, tag2, tag3
Standfirst: 1-2 zdania z key facts newsa.
Co się stało: jedno krótkie zdanie operacyjne.
Dlaczego ważne: jedno zdanie o wpływie lub konsekwencji.
Pełny opis:
2-4 unikalne akapity zaawansowanego kontekstu z dodatkowego researchu.

Kontekst:
- Co się stało: ...
- Dlaczego ważne: ...
- Na co patrzeć dalej: ...
Źródła:
- [Nazwa](https://...)
```

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
notyfikacji push. Najpierw uruchom wspólny kontrakt publikacji:

`python3 scripts/pavbot_publication_contract.py prepare research/polska-swiat`

`python3 scripts/pavbot_publication_contract.py verify-local research/polska-swiat`

To jest pipeline `prepare -> validate -> manifest -> push -> verify-remote`.
Etap `manifest` oznacza uruchomienie
`python3 scripts/generate_pavbot_manifest.py --repo-root "$PWD"`. Skrypt
odświeża `public/pavbot-manifest.json`, commituje tylko dozwolone ścieżki i
robi push na `origin/main`.
Skrypt sam wyprowadza `PAVBOT_MANIFEST_URL` z override środowiskowego,
`PAVBOT_RAW_BASE_URL`, istniejącego `rawBaseUrl` w manifeście albo GitHub
`origin`; ustaw zmienną ręcznie tylko dla niestandardowego URL. Rozwiązany URL
musi odpowiadać iOS `Settings -> Manifest URL`. Następnie uruchom:
`scripts/pavbot_commit_and_push_outputs.sh --isolated --force-manifest research/polska-swiat`.
Po pushu wykonaj `git fetch origin` i potwierdź, że `origin/main` zawiera
bieżące ścieżki `runs/YYYY-MM-DD.md`, `data/YYYY-MM-DD-research.json` i
`pdfs/YYYY-MM-DD-polska-swiat.pdf`, a zdalny manifest zawiera dla nich wpisy
`run`, `researchData` i `pdf`.

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
