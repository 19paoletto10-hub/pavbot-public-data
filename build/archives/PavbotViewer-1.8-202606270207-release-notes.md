# Pavbot Intelligence 1.8 (202606270207)

## TestFlight Notes

- Naprawiono zgodność wersji aplikacji i rozszerzenia Live Activity/Widget: app i extension używają teraz wspólnego `MARKETING_VERSION = 1.8`.
- Usunięto ryzyko błędu App Store Connect: `CFBundleShortVersionString of an app extension must match parent app`.
- Zachowano poprawki pogody, ręcznej lokalizacji, TTS/audio, haptics i mikrointerakcji z poprzedniego builda.

## Smoke Test

1. Wgraj build `1.8 (202606270207)` do TestFlight.
2. Sprawdź uruchomienie aplikacji i zakładkę `Dzisiaj`.
3. Sprawdź `Research -> Aktualne`, TTS/audio i `Puls Dnia`.
4. Potwierdź, że upload nie zgłasza mismatchu wersji extension.
