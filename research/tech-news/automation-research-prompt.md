# Automation Prompt: Pavbot Tech Research 08:00

```text
$daily-research-agent

Uruchom codzienny research technologiczny dla `research/tech-news`.
Pracuj po polsku i używaj poprawnych polskich znaków. Przeczytaj `AGENTS.md`, `docs/architecture.md`,
`research/tech-news/topic.md`, `research/tech-news/index.md`,
`research/tech-news/backlog.md` i najnowszy raport dzienny, jeśli istnieje.

Sprawdź aktualne publiczne źródła internetowe dotyczące globalnych nowinek
technologicznych, AI, startupów, produktów, regulacji i trendów. Korzystaj z
publicznych serwisów informacyjnych i źródeł pierwotnych, m.in. TVN24, WP,
Business Insider, Hacker News, Reddit, Product Hunt, oficjalnych blogów firm i
dużych portali technologicznych. Nie wymagaj logowania do social mediów.

Zapisz dzisiejszy raport do `research/tech-news/runs/YYYY-MM-DD.md`. Raport ma
zawierać linki do wszystkich materialnych źródeł, rozdział "Nowe fakty" oraz
sekcję "Tematy do podcastu" z 5-8 kandydatami. Przy każdym kandydacie podaj:
tytuł, dlaczego to ważne, główne źródła i priorytet.

Dodatkowo wygeneruj estetyczny, profesjonalny PDF z tym samym researchem do
`research/tech-news/pdfs/YYYY-MM-DD-tech-news.pdf`, używając
`scripts/render_research_pdf.py`. Po wygenerowaniu wyrenderuj strony PDF do PNG
i sprawdź wizualnie układ, polskie znaki, tabelę tematów oraz stopki.

Zaktualizuj `research/tech-news/index.md`, gdy zmienia się obecny stan wiedzy.
Zaktualizuj `research/tech-news/backlog.md`, gdy pojawiają się konkretne
follow-upy, notatki przeglądowe, pytania albo rozwiązane elementy.

Po zapisaniu artefaktów opublikuj wyniki dla aplikacji iOS i webhooka
notyfikacji push. Skrypt uruchamia `python3 scripts/generate_pavbot_manifest.py`,
odświeża `public/pavbot-manifest.json`, commituje tylko dozwolone ścieżki i robi
push na `origin/main`.
`PAVBOT_MANIFEST_URL` musi być ustawione w środowisku Codex albo repozytorium
na ten sam publiczny raw URL, który jest w iOS `Settings -> Manifest URL`;
aplikacja iOS nie przekazuje tej wartości z powrotem do Codex. Następnie
uruchom:
`scripts/pavbot_commit_and_push_outputs.sh research/tech-news`.

Użyj risk gate z `docs/architecture.md`. Jeśli rekomendowana akcja zmieniałaby
automatyzacje, instrukcje repo, skille, hooki, MCP, zależności albo pliki poza
aktywnym tematem, utwórz propozycję w `research/tech-news/proposals/` zamiast
stosować zmianę. Finalny krok publikacji może commitować tylko
`research/tech-news/` oraz `public/pavbot-manifest.json`.

Jeśli nie ma materialnych zmian, nadal utwórz krótki raport z `Status: No
material change`, sprawdzonymi źródłami i jednym zdaniem podsumowania.
```
