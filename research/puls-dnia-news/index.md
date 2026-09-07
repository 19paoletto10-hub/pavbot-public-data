# Puls Dnia News Index

## Current State

Slot 2026-09-07 12:06 przesuwa feed z porannych zdarzeń drogowych w stronę spraw kryminalnych i sądowych w Polsce oraz twardych alertów świata: lawiny w Rosji, eksplozji w Meksyku, zakłóceń lotniczych w Indonezji, huraganu Lowell na Hawajach, sygnałów Trumpa wobec Ukrainy i symbolicznej polityki w USA. Nadal dominuje operacyjny, bezpieczeństwowy charakter pulsu.

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
- Current emphasis should stay on criminal proceedings, public safety, volcanic and hurricane alerts, Ukraine signaling, symbol politics in the US, trade frictions and AI listing risk.
- Keep Gdańsk safety, Zondacrypto, granatnik, Indonesia-air-closure, Hawaii-hurricane and Anthropic cards ready for the next carousel refresh.
