# Proposal: Stabilize male-xtts workflow

Date: 2026-06-26
Topic: aktualne-wydarzenia-mobile
Risk: Medium

## Proposed Change

Ustabilizować generowanie wariantu `male-xtts` w pipeline aktualnych wydarzeń
przez wprowadzenie kontrolowanego timeoutu, wyraźnego wykrywania zawieszenia
oraz bezpiecznego fallbacku diagnostycznego bez blokowania całego runu.

## Reason

Trzy kolejne produkcyjne runy zakończyły się poprawnym audio
`female-piper`, ale zawieszeniem `male-xtts`. Problem nie dotyczy treści
tematu, tylko wspólnego workflow TTS i narzędzi poza aktywnym artefaktem
badawczym. Dalsze liczenie na sam retry nie jest już wystarczająco rygorystyczne.

## Files Or Settings Affected

- `.agents/scripts/podcast/render-podcast-audio.sh`
- `research/aktualne-wydarzenia-mobile/tools/render_two_tts_variants.sh`
- Lokalne środowisko XTTS w `~/.cache/pavbot/venvs/xtts/`
- Konfiguracja timeoutów albo watchdog dla renderu XTTS

## Acceptance Criteria

- `male-xtts` kończy się sukcesem albo porażką w ograniczonym, przewidywalnym czasie.
- Zawieszenie jednego wariantu nie blokuje zapisania `tts_variants.json`.
- W przypadku porażki pipeline zapisuje czytelny status błędu bez tworzenia
  fałszywego `podcast.mp3`.
- Co najmniej dwa kolejne runy produkcyjne kończą się bez ręcznego przerywania
  procesu XTTS.

## Rollback

Wycofać zmiany w timeoutach i obsłudze fallbacku, przywracając poprzedni sposób
uruchamiania XTTS, jeśli nowa logika obniży jakość audio albo zepsuje poprawny
render innych wariantów.
