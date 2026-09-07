# Puls Dnia News Index

## Current State

Slot 2026-09-07 21:01 przesuwa ciężar z porannego pakietu prokuratorsko-sądowego na krajową politykę i pogodę: Tusk ostrzy spór o AfD, Kraków weryfikuje podpisy kandydatów, a Black Hawk i wichury trzymają część krajowych alertów. W tle pozostają wojna dyplomatyczna wokół Ukrainy, VW, Kanada, OpenAI, Spectrum oraz wysokie alerty z Hawajów, Indonezji i Japonii.

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
- Current emphasis should stay on political friction around AfD, court and election procedure in Kraków, weather and wind damage, EU/US trade friction, AI safety, industrial defense conversion and tropical alerts.
- Keep Tusk-AfD, Kraków signatures, Black Hawk, wind damage, IMGW forecast, OpenAI-agents, Spectrum, VW-defense, Canada-tariffs, Hawaii-hurricane, Indonesia-air-closure and Japan-rain cards ready for the next carousel refresh.
