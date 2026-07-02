# Proposal: Recover mobile audio pipeline after ffmpeg breakage

Date: 2026-06-30
Topic: aktualne-wydarzenia-mobile
Risk: Medium

## Proposed Change

Naprawić wspólny pipeline renderu MP3 używany przez mobilny brief tak, aby
wariant `female-piper` znowu kończył się poprawnym plikiem `podcast.mp3`, a
wariant `male-xtts` kończył się sukcesem albo przewidywalną porażką bez
blokowania całego runu.

## Reason

Run `2026-06-30-1015` ujawnił nowy problem poza samym XTTS. `male-xtts`
dziewiąty raz z rzędu przekroczył timeout, ale dodatkowo standardowa ścieżka
`female-piper`, wcześniej stabilna, przestała kończyć render MP3 z powodu
lokalnego błędu linkowania `ffmpeg` do `libx265.215.dylib`. Ten pojedynczy run
udało się domknąć ręcznym obejściem lokalnym i publikacją prawdziwego pliku
`female-piper/podcast.mp3`, ale nie jest to trwała naprawa. Problem dotyczy
już nie jednego wariantu głosu, tylko współdzielonego etapu konwersji audio
poza aktywnym tematem badawczym.

## Files Or Settings Affected

- `.agents/scripts/podcast/render-podcast-audio.sh`
- `research/aktualne-wydarzenia-mobile/tools/render_two_tts_variants.sh`
- Lokalne środowisko `ffmpeg`/`ffprobe` oraz biblioteki `x265`
- Lokalne środowisko XTTS w `~/.cache/pavbot/venvs/xtts/`

## Acceptance Criteria

- `female-piper` ponownie tworzy poprawny `podcast.mp3` bez ręcznego obejścia w
  środowisku uruchomieniowym.
- `male-xtts` kończy się sukcesem albo kontrolowaną porażką w ograniczonym
  czasie i nie blokuje zapisania `tts_variants.json`.
- Pipeline nie publikuje placeholderów i zachowuje tylko realne pliki MP3.
- Co najmniej dwa kolejne produkcyjne runy kończą render audio bez ręcznego
  przerywania procesu i bez błędu `ffmpeg`/`x265`.

## Rollback

Wycofać zmianę sposobu wywoływania `ffmpeg`, timeoutów albo fallbacków, jeśli
naprawa pogorszy jakość audio, złamie zgodność metadanych TTS albo wprowadzi
niestabilność w innych topicach korzystających ze wspólnego renderera.
