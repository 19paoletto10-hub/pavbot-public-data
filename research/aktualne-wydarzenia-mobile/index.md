# Topic Index: aktualne-wydarzenia-mobile

Last updated: 2026-06-23

## Current Understanding

Ten temat służy do codziennego tworzenia mobilnego briefu o aktualnych
wydarzeniach. Wynikiem ma być krótki, źródłowany raport Markdown, estetyczny PDF
pod ekrany mobilne oraz scenariusz podcastowy po polsku z dwoma wariantami TTS:
żeńskim Piper i męskim XTTS.

Testowy run z 2026-06-23 utworzył pełny zestaw artefaktów: raport Markdown,
mobilny PDF, scenariusz podcastowy oraz dwa pliki MP3. Najmocniejszy zestaw
źródeł na start to KPRM/Gov.pl, Consilium, AP News, NATO, IMGW i RCB.

## Stable Facts

- Materiał ma korzystać z aktualnych, wiarygodnych źródeł i zachowywać linki do
  materialnych twierdzeń. Source: [Topic contract](topic.md).
- PDF ma być projektowany pod szybkie czytanie na telefonie, z faktami,
  interpretacją i źródłami oddzielonymi wizualnie. Source: [Topic contract](topic.md).
- TTS ma powstawać w dwóch wariantach z prędkością finalną 1.1x oraz metadanymi
  języka. Source: [Automation prompt](automation-prompt.md).

## Open Questions

- Które źródła będą regularnie najlepsze dla krótkiego mobilnego briefu bez
  nadmiernego szumu?
- Czy po pierwszych trzech runach zmienić liczbę tematów lub ton humoru w
  scenariuszu?

## Watch Items

- Jakość linków źródłowych przy materialnych twierdzeniach.
- Czy PDF renderuje się czytelnie na wąskim ekranie.
- Czy oba warianty TTS powstają i zapisują status w `tts_variants.json`.
- Czy humor pozostaje lekki i nie osłabia powagi tematów bezpieczeństwa,
  konfliktów, tragedii lub spraw publicznych.

## Recent Reports

- [2026-06-23](runs/2026-06-23.md) - testowy run z PDF i dwoma wariantami TTS.
