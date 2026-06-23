# Automation Prompt: Pavbot Aktualne Wydarzenia Mobile 10:15

```text
$daily-research-agent

Uruchom kompletny codzienny workflow dla
`research/aktualne-wydarzenia-mobile`. Pracuj po polsku i używaj poprawnych
polskich znaków.

Najpierw przeczytaj `AGENTS.md`, `docs/architecture.md`,
`research/aktualne-wydarzenia-mobile/topic.md`,
`research/aktualne-wydarzenia-mobile/index.md`,
`research/aktualne-wydarzenia-mobile/backlog.md` oraz najnowszy raport z
`research/aktualne-wydarzenia-mobile/runs/`, jeśli istnieje.

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
`research/aktualne-wydarzenia-mobile/runs/YYYY-MM-DD.md`. Raport ma zawierać:
datę, status `Material update` albo `No material change`, zakres sprawdzonych
źródeł, krótkie podsumowanie, sekcję `Nowe fakty`, sekcję `Interpretacja`,
ryzyka/niepewności, rekomendowane akcje i źródła. Zachowaj linki przy każdym
materialnym twierdzeniu. Oddziel fakty od interpretacji.

Następnie przygotuj folder podcastu:
`research/aktualne-wydarzenia-mobile/podcasts/YYYY-MM-DD/`. Utwórz `draft.md`,
zweryfikuj twierdzenia wobec źródeł i zapisz finalny `script.md`. Scenariusz ma
być po polsku, bez surowych URL-i, gotowy pod podcastowy TTS z automatycznie
wykrywanym językiem. Dodaj lekki, inteligentny humor tylko tam, gdzie nie
umniejsza powagi wydarzeń. Liczby, daty, skróty i nazwiska zapisuj naturalnie
dla lektora. Utwórz `sources.md` z sekcjami:
`## Źródła użyte w scenariuszu`,
`## Źródła sprawdzone, ale niewykorzystane`,
`## Źródła niedostępne lub niejednoznaczne`.

Uruchom lint redakcyjny:
`bash .agents/scripts/podcast/editorial_lint.sh research/aktualne-wydarzenia-mobile/podcasts/YYYY-MM-DD/script.md research/aktualne-wydarzenia-mobile/podcasts/YYYY-MM-DD/sources.md`.

Wygeneruj PDF pod ekrany mobilne:
`~/.cache/pavbot/venvs/pdf/bin/python research/aktualne-wydarzenia-mobile/tools/render_mobile_brief_pdf.py research/aktualne-wydarzenia-mobile/runs/YYYY-MM-DD.md research/aktualne-wydarzenia-mobile/podcasts/YYYY-MM-DD research/aktualne-wydarzenia-mobile/pdfs/YYYY-MM-DD-mobile-brief.pdf --topic aktualne-wydarzenia-mobile`.

Wygeneruj dwa warianty TTS:
`bash research/aktualne-wydarzenia-mobile/tools/render_two_tts_variants.sh research/aktualne-wydarzenia-mobile/podcasts/YYYY-MM-DD/script.md research/aktualne-wydarzenia-mobile/podcasts/YYYY-MM-DD`.

Warianty audio mają być zapisane jako:
- `research/aktualne-wydarzenia-mobile/podcasts/YYYY-MM-DD/audio/female-piper/podcast.mp3`
- `research/aktualne-wydarzenia-mobile/podcasts/YYYY-MM-DD/audio/male-xtts/podcast.mp3`

Zapisz zbiorcze metadane w
`research/aktualne-wydarzenia-mobile/podcasts/YYYY-MM-DD/tts_variants.json`.
Jeśli jeden wariant TTS zawiedzie, nie twórz fałszywego MP3; zachowaj raport,
PDF, skrypt, źródła i zapisz błąd w metadanych oraz backlogu.

Po zapisaniu artefaktów opublikuj wyniki dla aplikacji iOS i webhooka
notyfikacji push. Skrypt uruchamia `python3 scripts/generate_pavbot_manifest.py`,
odświeża `public/pavbot-manifest.json`, commituje tylko dozwolone ścieżki i robi
push na `origin/main`.
`PAVBOT_MANIFEST_URL` musi być ustawione w środowisku Codex albo repozytorium
na ten sam publiczny raw URL, który jest w iOS `Settings -> Manifest URL`;
aplikacja iOS nie przekazuje tej wartości z powrotem do Codex. Następnie
uruchom:
`scripts/pavbot_commit_and_push_outputs.sh research/aktualne-wydarzenia-mobile`.

Użyj risk gate z `docs/architecture.md`. W ramach tej automatyzacji wolno
zmieniać tylko pliki w `research/aktualne-wydarzenia-mobile/` oraz manifest
publiczny generowany ze źródeł. Finalny krok publikacji może commitować tylko
`research/aktualne-wydarzenia-mobile/` oraz `public/pavbot-manifest.json`. Jeśli rekomendowana akcja wymaga zmiany
automatyzacji, instrukcji repo, skilli, hooków, MCP, zależności albo plików poza
aktywnym tematem, utwórz propozycję w
`research/aktualne-wydarzenia-mobile/proposals/` zamiast stosować zmianę.
```
