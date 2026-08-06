# Puls Dnia News Index

## Current State

Slot z 2026-08-06 18:04 przesuwa feed ku energetyce operacyjnej: PSE ogłasza okresy przywołania 17:00-22:00, IMGW i RCB utrzymują alerty burzowo-upałowe, a TVN24 dokłada OKI, atak na Żabkę, wyrok w sprawie Ryanaira i rekord Radomia.

Za granicą BBC i CNN dalej trzymają Lipsk, Kijów, Hormuz, Iran i Kanał La Manche, a Meta dorzuca kolejny incydent AI do już i tak napiętego bloku technologicznego.

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
