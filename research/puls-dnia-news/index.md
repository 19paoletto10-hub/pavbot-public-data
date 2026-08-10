# Puls Dnia News Index

## Current State

Slot 2026-08-10 15:07 przesuwa feed na alerty pogodowe i RCB w Polsce, nowe ustalenia wokół drona i rosyjskiego pocisku, ORP Wicher oraz twardszy blok bezpieczeństwa z Ukrainy, Chin, Kanału La Manche i amerykańskiej polityki. W tym przebiegu technologia schodzi na dalszy plan, a główne ryzyka to pogoda, przestrzeń powietrzna, granice i presja geopolityczna.

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
- Current emphasis should stay on weather alerts, airspace incidents, border/security events, Ukraine/Russia, China storms and US institutional moves.
