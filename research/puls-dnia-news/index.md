# Puls Dnia News Index

## Current State

Slot 2026-08-21 15:02 przesuwa feed z porannych wątków energetyczno-regulacyjnych w stronę świeżych krajowych incydentów, nowego alertu pogodowego i kolejnej fali materiałów o bezpieczeństwie dzieci w AI. W centrum są Warszawa, Zakroczym, Ochota, Kraków, lex szarlatan, patronat Warszawy 44, RCB/IMGW, proces Mety, OpenAI oraz świeże tematy światowe i gospodarcze z Rosji i Wielkiej Brytanii.

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
- Favor stories with concrete official or primary links when they are available alongside TVN24, BBC or CNN.
- Current emphasis should stay on alert logic, public-safety incidents, AI child-safety litigation, OpenAI security hardening, UK fiscal/consumer pressure and concrete world disruption rather than softer feature content.
