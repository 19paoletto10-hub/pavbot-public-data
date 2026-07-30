# Puls Dnia News Index

## Current State

This topic powers the iOS `Dzisiaj -> Szybki puls dnia` carousel. The app first
looks for the newest `pulseNewsData` artifact in the public manifest. If none
exists, it falls back to the older `aktualne-wydarzenia-mobile` magazine data.
The public manifest now exposes timestamped `pulseNewsData` artifacts for this
topic, so the primary feed path is active when refresh succeeds.

The 2026-07-30 06:01 slot przesuwa feed z wczorajszego klastra PiS/RPO w stronę
transportu, upału, pożarów i ryzyk operacyjnych: metro w Warszawie kończy się
wydaleniem z Polski, Chorzów ma duży pożar w centrum, a za granicą najgłośniej
świecą Francja, Japonia, Wielka Brytania, ONZ, CNN-owy pakiet pożarowy i AI.

The 2026-07-29 21:07 slot domyka wieczór formalnym spotkaniem Kaczyński-
Morawiecki po terminie ultimatum, potwierdza wybór Sylwii Gregorczyk-Abram na
RPO i dokłada świeże, bieżące ryzyka z ONZ, Wielkiej Brytanii, Hiszpanii oraz
rynku pracy pod wpływem AI.

The 2026-07-29 12:01 slot przesuwa Puls Dnia z porannego rozłamu PiS do
bardziej formalnej fazy: nowy klub Morawieckiego, lista członków, spotkanie
Tuska z Zełenskim, paliwa i ranking zaufania zostają w kraju, a za granicą
ciężar przechodzą Irak, Portugalia, Francja, Japonia, chińskie roboty, OpenAI
i Durov.

The 2026-07-29 09:01 slot przesuwa Puls Dnia z porannego pakietu fiskalno-
instytucjonalnego w bardziej operacyjny miks: PiS, Warszawa, prokurator, upały
i burze zostają w kraju, a za granicą wchodzą greckie pożary, francuskie ognie,
japońskie trzęsienie ziemi, chińskie roboty i AI-policy CNN.

The live run contract is now active with timestamped Markdown and
`pulse-news.json` outputs using one shared Europe/Warsaw run stamp. Material
items are discovered from TVN24, BBC and CNN, then confirmed with official or
primary public sources when the claim is safety-, market- or policy-relevant.
The 2026-07-29 18:02 slot przesuwa feed z samego rozłamu w PiS w stronę
szerszego pakietu ryzyk: PiS nadal żyje ultimatum, Morawiecki i Czarnek
podtrzymują napięcie, paliwa wracają jako koszt życia, a Japonia, pożary w
Europie, Berlin, Seattle i OpenAI dorzucają kolejne ogniska ryzyka.
The 21:05 slot on 2026-07-07 added late-evening items on wind alerts, an
evacuation in Krynica Morska, Ziobro extradition, Toyota's Texas expansion,
Le Pen, NATO, Farage, Hungary's state TV reset, Gaza and China.

The 2026-07-08 12:01 slot shifted the domestic mix toward very strong wind in
the north, healthcare reform signals, a BBN reaction to Budanow and a custody
death, while the international feed stayed anchored in Iran-US escalation,
NATO procurement, Le Pen, Farage, Russian fuel shortages, Kyiv strikes, China
and Monaco.

The 2026-07-08 15:02 slot hardened the domestic feed around an active wind
alert, a sharp cold snap, unchanged rates, health-system recommendations,
BBN comments on Budanow and a worsening unemployment trend. The world feed
stayed centered on Iran-US escalation, NATO procurement, Le Pen, Russian fuel
shortages and China weather, while also adding a telecom outage in Australia.

The 2026-07-08 18:03 slot added fresh domestic items on renewed storm
pressure, evacuated harcerze, new scanners at Chopin, PIP reform and AI
dezinformation, while the world feed strengthened around Iran, Ukraine/NATO,
Le Pen, Russian fuel shortages, Telstra and severe weather in China.

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
