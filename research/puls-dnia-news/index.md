# Puls Dnia News Index

## Current State

This topic powers the iOS `Dzisiaj -> Szybki puls dnia` carousel. The app first
looks for the newest `pulseNewsData` artifact in the public manifest. If none
exists, it falls back to the older `aktualne-wydarzenia-mobile` magazine data.

The live run contract is now active with timestamped Markdown and
`pulse-news.json` outputs using one shared Europe/Warsaw run stamp. Material
items are discovered from TVN24, BBC and CNN, then confirmed with official or
primary public sources when the claim is safety-, market- or policy-relevant.

## Data Shape

The native iOS feed expects:

- one digest headline and summary;
- at least 12 news items;
- an even number of items;
- sections such as `Polska`, `Świat`, `Polityka`, `Bezpieczeństwo`,
  `Gospodarka`, `Technologia`, `Alerty`;
- source links for every item;
- analysis fields: `whatHappened`, `keyFacts`, `reactions`, `whyItMatters`,
  `context`, `watchNext`.

## iOS Surface

The newest valid JSON is shown as paired cards under `Dzisiaj`. Tapping a card
opens a detail view with facts, reactions, context, why it matters, watch-next
items and sources.

## Editorial Notes

- Keep at least 12 items and an even count so the app renders exact card pairs.
- Keep at least two `Polska` or `Polityka` items and at least two `Świat`
  items to protect the home feed balance.
- Prefer operational alerts, public-safety events, geopolitics and major
  economy moves over softer feature content.
