# Puls Dnia News Index

## Current State

Slot 2026-08-06 21:03 potwierdza twardy blok pogodowo-energetyczny: 38 stopni w Cieszanowie, alerty IMGW/RCB i okresy przywołania PSE na 17:00-22:00 dalej trzymają krajowy feed w trybie operacyjnym.

W polityce ciężar przesunął się na pierwszy rok prezydentury Nawrockiego, kolejne odrzucenie wniosku o referendum klimatyczne przez Senat i odwołanie Beaty Szydło w sprawie PFN.

Za granicą najmocniej wybija Lipsk jako sygnał zagrożenia dla infrastruktury krytycznej, Ukraina i niedobór obrony powietrznej, Hormuz jako punkt nacisku na rynek ropy, Kanał La Manche jako stałe ryzyko humanitarne oraz AI, które wchodzi już w obszar biosafety i incydentów operacyjnych.

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
