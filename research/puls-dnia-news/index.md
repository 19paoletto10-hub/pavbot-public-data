# Puls Dnia News Index

## Current State

Slot 2026-09-07 09:02 przesuwa feed z porannych alertów pogodowych w stronę krajowych wypadków drogowych, procesów i ruchu na drogach, a za granicą wzmacnia miks wokół AfD, Ukrainy, ropy, brytyjskiej gospodarki, Indonezji i ryzyk technologicznych. Nadal widać twardy, operacyjny charakter pulsu: transport, bezpieczeństwo, polityka i makroekonomia dominują nad lżejszymi tematami.

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
- Current emphasis should stay on transport incidents, Ukraine, napięciach politycznych w Europie, gospodarce UK, ropie, Indonezji i ryzykach AI.
- Keep road-disruption, Ukraine-response, oil, Indonesia-air-closure and technology-risk cards ready for the next carousel refresh.
