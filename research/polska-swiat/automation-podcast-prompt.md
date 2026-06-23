# Automation Prompt: Pavbot Polska Świat Podcast 09:30

```text
$daily-news-podcast-agent

Przygotuj dzisiejszy polski podcast wiadomości dla `research/polska-swiat`.
Pracuj po polsku i używaj pełnych polskich znaków diakrytycznych. Najpierw
przeczytaj dzisiejszy raport `research/polska-swiat/runs/YYYY-MM-DD.md`, jeśli
istnieje. Jeśli go brakuje, wykonaj awaryjny skrócony research publicznych
serwisów informacyjnych i zapisz to ograniczenie w `sources.md`.

Sprawdź jeszcze raz aktualne publiczne źródła newsowe dotyczące Polski i świata,
szczególnie polityki, wydarzeń, bezpieczeństwa, dyplomacji, decyzji rządów i
ważnych spraw społecznych. Korzystaj m.in. z TVN24, WP, Onet, Interia, RMF24,
Polsat News, Business Insider Polska, PAP jeśli publicznie dostępne, BBC,
Reuters/AP przez publicznie dostępne strony, The Guardian, Politico, Euronews i
oficjalnych komunikatów instytucji.

Wybierz 4-6 najmocniejszych tematów. Napisz profesjonalny, spokojny i dynamiczny
scenariusz po polsku na około 8 minut: intro, segmenty newsowe z kontekstem
"dlaczego to ważne" i krótkie zakończenie. Celuj w 1150-1350 polskich słów, ale
priorytetem jest długość audio 7:30-8:30 przy lokalnym głosie Zosia.

Zastosuj wspólny workflow `$daily-podcast-agent`: najpierw przygotuj `draft.md`,
potem zweryfikuj źródła, popraw tekst pod mowę i dopiero wtedy zapisz finalny
`script.md`. `script.md` ma być tekstem gotowym do czytania, bez surowych URL-i,
z pełnymi polskimi znakami, naturalnymi przejściami oraz liczbami i datami
zapisanymi przyjaźnie dla TTS.

Zapisz:
- `research/polska-swiat/podcasts/YYYY-MM-DD/draft.md`
- `research/polska-swiat/podcasts/YYYY-MM-DD/script.md`
- `research/polska-swiat/podcasts/YYYY-MM-DD/sources.md`
- `research/polska-swiat/podcasts/YYYY-MM-DD/render.json`
- `research/polska-swiat/podcasts/YYYY-MM-DD/brief.pdf`
- `research/polska-swiat/podcasts/YYYY-MM-DD/podcast.mp3`

Do audio użyj wspólnego lokalnego renderera: `bash .agents/scripts/podcast/render-podcast-audio.sh research/polska-swiat/podcasts/YYYY-MM-DD/script.md research/polska-swiat/podcasts/YYYY-MM-DD/podcast.mp3`. Domyślnie działa `PAVBOT_TTS_ENGINE=auto`: XTTS-v2, potem Piper, potem macOS `say -v Zosia`.

Po utworzeniu `render.json` przygotuj estetyczny profesjonalny PDF:
`~/.cache/pavbot/venvs/pdf/bin/python .agents/scripts/podcast/render-podcast-brief-pdf.py research/polska-swiat/podcasts/YYYY-MM-DD`

Po zapisaniu artefaktów podcastu opublikuj wyniki dla aplikacji iOS i webhooka
notyfikacji push. Skrypt uruchamia `python3 scripts/generate_pavbot_manifest.py`,
odświeża `public/pavbot-manifest.json`, commituje tylko dozwolone ścieżki i robi
push na `origin/main`.
`PAVBOT_MANIFEST_URL` musi być ustawione w środowisku Codex albo repozytorium
na ten sam publiczny raw URL, który jest w iOS `Settings -> Manifest URL`;
aplikacja iOS nie przekazuje tej wartości z powrotem do Codex. Następnie
uruchom:
`scripts/pavbot_commit_and_push_outputs.sh research/polska-swiat`.

Nie zmyślaj faktów. Jeśli źródło jest niedostępne lub niejednoznaczne, zapisz to
w `sources.md` i nie używaj niepotwierdzonego twierdzenia w podcaście.
```
