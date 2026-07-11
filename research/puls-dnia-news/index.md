# Puls Dnia News Index

## Current State

This topic powers the iOS `Dzisiaj -> Szybki puls dnia` carousel. The app first
looks for the newest `pulseNewsData` artifact in the public manifest. If none
exists, it falls back to the older `aktualne-wydarzenia-mobile` magazine data.
The public manifest now exposes timestamped `pulseNewsData` artifacts for this
topic, so the primary feed path is active when refresh succeeds.

The live run contract is now active with timestamped Markdown and
`pulse-news.json` outputs using one shared Europe/Warsaw run stamp. Material
items are discovered from TVN24, BBC and CNN, then confirmed with official or
primary public sources when the claim is safety-, market- or policy-relevant.
The 2026-07-10 12:08 slot moved the feed toward Jedwabne, Bosacki's warning
to Kyiv, the Myrcha immunity request, PAŻP financing pressure after the
Pfizer ruling, NBP's new inflation projection, a British tobacco-packaging
plan, SK Hynix's New York debut, U.S. restrictions aimed at Chinese autos,
heat alerts, and renewed BBC/CNN signals on Iran and China.
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

The 2026-07-10 06:00 slot shifted the pulse toward criminal and institutional
news: the NIK indictment, PAŻP financing risk after the Pfizer ruling,
Obajtek's clash at Solino, the Łódź rape case, and the Poznań spy-related
incident dominated Poland. The world feed added Farage, the Austrian burkini
judgment, Erdogan's diplomatic gift, OpenAI's ChatGPT Work launch, NASA's
Swift boost mission and the lingering Bałtyk storm aftermath.

The 2026-07-10 15:01 slot moved the feed again, this time toward the Kaczyński
and Tusk clash, Obajtek in Solino, the Katowice children's oncology warning,
the Mokotów robbery, the Poznań car arsons and a weather warm-up to nearly 30
degrees. BBC and CNN added fresh world pressure from the East Asia typhoon,
SK Hynix's US share sale, US-Iran talks, Spanish wildfires, China’s reusable
rocket breakthrough and Ukraine’s strikes near Crimea.

The 2026-07-10 18:01 slot pushed the domestic feed toward Romanowski, the
Ukraine-Moldova EU step, illegal medicines, the Fundacja TVN psychotherapy
program, doctors' pay data and an IMGW thunderstorm alert. BBC and CNN
shifted the world mix toward the East Asia typhoon, the Houston ICE shooting,
the Ryanair window incident, UAP video declassification, China's reusable
rocket test and renewed Iran talks.

The 2026-07-10 21:01 slot moved the feed into a more operational mix:
Ursynów police violence, illegal meds, PAŻP financing pressure, a Mława
illegal tobacco factory, Czarzasty and Ukraine's EU path, Trump's Iran
warnings, Spanish wildfires, the East Asia typhoon, Ryanair's window failure,
Meta's DSA trouble and China's reusable rocket milestone.

The 2026-07-11 09:04 slot moved the domestic mix toward Kaczyński, Wołyń,
IMGW storm alerts and a Lubelszczyzna funnel cloud, while the world feed now
leans harder into Hormuz negotiations, Russian shipping disruptions, Ukraine's
attacks on Russian energy infrastructure, WHO's bigger-Ebola warning, the CNN
case in DRC, the Spanish wildfire and Meta's AI rollback.

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
