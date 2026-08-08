# Puls Dnia News Index

## Current State

Slot 2026-08-08 12:06 przesuwa feed z poprzedniego bloku pogodowo-energetycznego na bezpieczeństwo publiczne, alerty zdrowotne i transportowe oraz mocniejsze wątki zagraniczne. W kraju dominują warszawska akcja policji przeciw narkobiznesowi, pożar auta z namiotem w Chorzowie, komunikat GIS o wycofaniu napoju i ognisko gruźlicy w przedszkolu na Białołęce.

Za granicą ciężar leży na wojnie w Ukrainie, tajfunie Dolphin w Azji Wschodniej, sporze migracyjnym Hiszpania-Włochy, brytyjskich śledztwach policyjnych i amerykańskiej polityce wyborczej. CNN nadal pokazuje redystrybucję okręgów i tracker działań odwetowych Trumpa jako żywe wątki instytucjonalne.

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
