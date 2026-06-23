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

Zaktualizuj `research/polska-swiat/index.md`, gdy zmienia się obecny stan
wiedzy. Zaktualizuj `research/polska-swiat/backlog.md`, gdy pojawiają się
konkretne follow-upy, notatki przeglądowe, pytania albo rozwiązane elementy.

Po zapisaniu artefaktów opublikuj wyniki dla aplikacji iOS i webhooka
notyfikacji push. Skrypt uruchamia `python3 scripts/generate_pavbot_manifest.py`,
odświeża `public/pavbot-manifest.json`, commituje tylko dozwolone ścieżki i robi
push na `origin/main`.
`PAVBOT_MANIFEST_URL` musi być ustawione w środowisku Codex albo repozytorium
na ten sam publiczny raw URL, który jest w iOS `Settings -> Manifest URL`;
aplikacja iOS nie przekazuje tej wartości z powrotem do Codex. Następnie
uruchom:
`scripts/pavbot_commit_and_push_outputs.sh research/polska-swiat`.

Użyj risk gate z `docs/architecture.md`. Jeśli rekomendowana akcja zmieniałaby
automatyzacje, instrukcje repo, skille, hooki, MCP, zależności albo pliki poza
aktywnym tematem, utwórz propozycję w `research/polska-swiat/proposals/`
zamiast stosować zmianę. Finalny krok publikacji może commitować tylko
`research/polska-swiat/` oraz `public/pavbot-manifest.json`.

Jeśli nie ma materialnych zmian, nadal utwórz krótki raport z `Status: No
material change`, sprawdzonymi źródłami i jednym zdaniem podsumowania.
```
