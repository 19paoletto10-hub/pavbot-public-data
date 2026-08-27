# Puls Dnia News Index

## Current State

Slot 2026-08-27 12:03 przesuwa feed na świeższe krajowe ruchy wokół Rozwoju Plus, Romanowskiego, wypadku busa i pościgu w Zielonce, a światowy rdzeń opiera na nowych atakach na Ukrainę, katastrofie w Nepalu, pożarze w Islamabadzie, wojnie handlowej USA-Kanada, sankcjach na Iran, ugodzie Mety i pożarze pod Barceloną.

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
