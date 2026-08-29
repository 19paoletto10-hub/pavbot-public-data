# Puls Dnia News Index

## Current State

Slot 2026-08-29 15:03 przesuwa feed na mocny pakiet: PKOl reaguje po areszcie Piesiewicza, Romanowski wraca przez trop Dubaju, budżet 2027 ma już konkretne liczby, rośnie bilans ataku pod Kijowem, a alerty pogodowe nadal trwają. Do tego dochodzą policyjne follow-upy z Gdańska i Łęcznej oraz regulacyjne ruchy Google i Mety.

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
- Current emphasis should stay on a strong Polish follow-up, public safety, platform regulation, economic pressure and fresh official reactions.
- The current 15:03 slot adds a fresher Ukraine casualty update and new police material from Gdańsk and Łęczna, so keep those classes ready for the next carousel refresh.
