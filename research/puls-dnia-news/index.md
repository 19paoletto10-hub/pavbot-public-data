# Puls Dnia News Index

## Current State

Slot 2026-08-07 19:15 przesuwa feed z wczorajszego bloku upałowo-energetycznego na lokalne podtopienia na Podkarpaciu, krótki powrót upału do 34 stopni i regulacyjno-gospodarcze skutki ceł na paczki z Chin. W polityce krajowej widać teraz głównie samorządowy start Łukasza Gibały oraz wejście w życie ustawy frankowej.

Za granicą dominują bezpieczeństwo i polityka instytucjonalna: zatrzymany projekt ballroomu Trumpa, kolejne ograniczanie birthright citizenship, pakt obronny Saudów, Turków i Pakistańczyków, rekordowa grzywna dla Mety, rosyjskie pociski balistyczne oraz zimowa akcja ratunkowa na Antarktydzie.

## Data Shape

The native iOS feed expects:

- one digest headline and summary;
- at least 12 news items;
- an even number of items;
- sections such as `Polska`, `Świat`, `Polityka`, `Bezpieczeństwo`, `Gospodarka`, `Technologia`, `Alerty`;
- source links for every item;
- analysis fields: `whatHappened`, `keyFacts`, `reactions`, `whyItMatters`, `context`, `watchNext`.

## iOS Surface

The newest valid JSON is shown as paired cards under `Dzisiaj`. Tapping a card opens a detail view with facts, reactions, context, why it matters, watch-next items and sources.

## Editorial Notes

- Keep at least 12 items and an even count so the app renders exact card pairs.
- Keep at least two `Polska` or `Polityka` items and at least two `Świat` items to protect the home feed balance.
- Prefer operational alerts, public-safety events, geopolitics and major economy moves over softer feature content.
