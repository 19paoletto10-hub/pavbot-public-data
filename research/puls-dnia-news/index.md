# Puls Dnia News Index

## Current State

Slot z 2026-08-05 21:06 utrzymuje przejście z czystej polityki do obrazu operacyjnego: mObywatel nadal generuje zgłoszenia, upał przechodzi w burze, a energia i paliwa pozostają głównym krajowym blokiem ryzyka. Polityka PiS nie zniknęła, ale nie dominuje już całego feedu.

Za granicą BBC i CNN nadal trzymają uwagę na Ukrainie, Niemczech, Iranie, globalnej energii i Kanale La Manche. AI pozostaje osobnym wątkiem regulacyjno-politycznym, teraz mocniej związanym z egzekwowaniem przejrzystości.

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
