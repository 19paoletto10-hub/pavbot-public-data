# Puls Dnia News Index

## Current State

Slot 2026-09-07 00:02 przesuwa feed w stronę mocnego pakietu krajowego i międzynarodowego: Zondacrypto dostało kolejne zatrzymanie, gen. Pytel został zdjęty z lotniska, EES wchodzi w pełne funkcjonowanie, IMGW ostrzega przed upałem i burzami, a za granicą dominują AfD, rozmowy USA-Rosja-Ukraina oraz nowe ruchy regulatorów wobec Google i Amazona.

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
- Prefer operational alerts, public safety, sanctions pressure, platform regulation and civil-protection stories over softer feature content.
- Favor stories with concrete official or primary links when they are available alongside TVN24, BBC or CNN.
- Current emphasis should stay on a strong Polish follow-up, public safety, EES/travel controls, platform regulation, and fresh official reactions from Ukraine and regulators.
- Keep weather, border-control and Ukraine-response cards ready for the next carousel refresh.
