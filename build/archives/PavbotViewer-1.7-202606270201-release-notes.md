# Pavbot Intelligence 1.7 (202606270201)

## TestFlight Notes

- Dzisiaj: dodano utwardzoną ręczną zmianę lokalizacji prognozy pogody.
- Pogoda: start aplikacji nie blokuje się na CoreLocation; domyślnie używa szybkiego fallbacku i cache.
- Pogoda: przy komunikacie `Bieżąca prognoza dla:` można otworzyć edytor miasta, zapisać lokalizację albo wrócić do domyślnego Wrocławia.
- Mac/iPad-on-Mac: poprawiona stabilność startu ekranu Dzisiaj i odświeżania pogody.
- Interakcje: zachowane mikrointerakcje i haptyka dla najważniejszych akcji aplikacji.

## Smoke Test

1. Otwórz `Dzisiaj` i sprawdź, że aplikacja nie pyta od razu o lokalizację.
2. Kliknij `Zmień` przy lokalizacji prognozy.
3. Wpisz np. `Warszawa`, zapisz i sprawdź, czy pogoda ładuje się dla zapisanej lokalizacji.
4. Przywróć domyślny Wrocław.
5. Na iPad/Mac Designed for iPad przełącz kilka zakładek po starcie i sprawdź brak zawieszenia UI.
