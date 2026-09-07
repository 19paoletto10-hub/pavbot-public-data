# Puls Dnia News Index

## Current State

Slot 2026-09-07 06:02 przesuwa feed w stronę alertów pogodowych, travel disruption i świeżych kart międzynarodowych: Zondacrypto dostaje kolejny redakcyjny przegląd, IMGW ostrzega przed upałem, burzami i silnym deszczem, pożar pod Wrocławiem oraz zakłócenia lotnicze w Indonezji podbijają alerty, a za granicą dominują Ukraina, AfD, brytyjska gospodarka, JLR, ryzyka AI i napięcia bezpieczeństwa w USA oraz Wielkiej Brytanii.

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
- Prefer operational alerts, public safety, travel disruption, platform risk and civil-protection stories over softer feature content.
- Favor stories with concrete official or primary links when they are available alongside TVN24, BBC or CNN.
- Current emphasis should stay on alertach pogodowych, ruchu lotniczym, Ukrainie, napięciach politycznych w Europie, gospodarce UK i ryzykach AI.
- Keep weather, border-control, Ukraine-response and technology-risk cards ready for the next carousel refresh.
