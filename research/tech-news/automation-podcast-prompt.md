# Automation Prompt: Pavbot Tech Podcast 09:00

```text
$daily-tech-podcast-agent

Przygotuj dzisiejszy polski podcast technologiczny dla `research/tech-news`.
Pracuj po polsku i używaj pełnych polskich znaków diakrytycznych. Najpierw
przeczytaj dzisiejszy raport `research/tech-news/runs/YYYY-MM-DD.md`, jeśli
istnieje. Jeśli go brakuje, wykonaj awaryjny skrócony research publicznych
serwisów informacyjnych i zapisz
to ograniczenie w `sources.md`.

Sprawdź jeszcze raz aktualne publiczne źródła newsowe, szczególnie tematy
global tech i AI oraz źródła istotne dla polskiego odbiorcy, m.in. TVN24, WP,
Business Insider, Hacker News, Reddit, Product Hunt, oficjalne blogi firm i
duże portale technologiczne. Nie wymagaj logowania do social mediów.

Wybierz 4-6 najmocniejszych tematów. Napisz profesjonalny, dynamiczny
scenariusz po polsku na około 8 minut: intro, segmenty newsowe z kontekstem
"dlaczego to ważne" i krótkie zakończenie. Celuj w 1250-1350 polskich słów.

Zastosuj wspólny workflow `$daily-podcast-agent`: najpierw przygotuj `draft.md`,
potem zweryfikuj źródła, popraw tekst pod mowę i dopiero wtedy zapisz finalny
`script.md`. `script.md` ma być tekstem gotowym do czytania, bez surowych URL-i,
z pełnymi polskimi znakami, naturalnymi przejściami oraz liczbami i datami
zapisanymi przyjaźnie dla TTS.

Zapisz:
- `research/tech-news/podcasts/YYYY-MM-DD/draft.md`
- `research/tech-news/podcasts/YYYY-MM-DD/script.md`
- `research/tech-news/podcasts/YYYY-MM-DD/sources.md`
- `research/tech-news/podcasts/YYYY-MM-DD/render.json`
- `research/tech-news/podcasts/YYYY-MM-DD/brief.pdf`
- `research/tech-news/podcasts/YYYY-MM-DD/podcast.mp3`

Do audio użyj wspólnego lokalnego renderera:
`bash .agents/scripts/podcast/render-podcast-audio.sh
research/tech-news/podcasts/YYYY-MM-DD/script.md
research/tech-news/podcasts/YYYY-MM-DD/podcast.mp3`
Domyślnie działa `PAVBOT_TTS_ENGINE=auto`: XTTS-v2, potem Piper, potem macOS
`say -v Zosia`.

Po utworzeniu `render.json` przygotuj estetyczny profesjonalny PDF:
`~/.cache/pavbot/venvs/pdf/bin/python .agents/scripts/podcast/render-podcast-brief-pdf.py research/tech-news/podcasts/YYYY-MM-DD`
PDF ma być mobile-first premium: format telefonu 390 x 844 pt, czytelny bez
zoomu w aplikacji Pavbot, z kartami metadanych audio, widocznymi linkami źródeł
i bez surowych URL-i w głównej treści. Po renderze wyrenderuj strony do PNG i
sprawdź wizualnie spacing, stopki, polskie znaki oraz brak ucięć tekstu.

Po zapisaniu artefaktów podcastu opublikuj wyniki dla aplikacji iOS i webhooka
notyfikacji push. Skrypt uruchamia `python3 scripts/generate_pavbot_manifest.py`,
odświeża `public/pavbot-manifest.json`, commituje tylko dozwolone ścieżki i robi
push na `origin/main`.
Skrypt sam wyprowadza `PAVBOT_MANIFEST_URL` z override środowiskowego,
`PAVBOT_RAW_BASE_URL`, istniejącego `rawBaseUrl` w manifeście albo GitHub
`origin`; ustaw zmienną ręcznie tylko dla niestandardowego URL. Rozwiązany URL
musi odpowiadać iOS `Settings -> Manifest URL`. Następnie uruchom:
`scripts/pavbot_commit_and_push_outputs.sh --isolated research/tech-news`.

Nie zmyślaj faktów. Jeśli źródło jest niedostępne lub niejednoznaczne, zapisz
to w `sources.md` i nie używaj niepotwierdzonego twierdzenia w podcaście.
```
