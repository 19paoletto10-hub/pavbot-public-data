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

The 2026-07-09 06:02 slot shifted the feed away from the wczorajszy blok
health-macro toward legal and political items in Poland, alert-heavy weather,
and a new global mix centered on Iran, Grenlandia, Le Pen, France fires and
the German doctor verdict. For the current morning cadence, direct article
pages are more reliable than bundle headlines when TVN24 exposes them.

The 2026-07-09 09:01 slot adds a more operational domestic mix around health
reform, the Poznań anti-Ukrainian incident, the S8 korytarz życia problem and
IMGW storm alerts. Abroad, the lead remains Iran and NATO, but the slot now
also carries Sudan war-crimes reporting, Kyiv strikes, Le Pen, Farage,
Hormuz shipping risk, a Chinese missile test, steady NBP rates and two fresh
CNN tech items about Microsoft and Anthropic.

The 2026-07-09 12:02 slot keeps the domestic core on health, Poznań, S8,
Chopin and RPP, but adds a clearer transport and market layer: new skaners at
Chopin, a stronger oil-market reaction to the Middle East and continued
weather pressure on the north. Internationally, Iran stays central, while
NATO/Ukraina, Le Pen and Grenlandia remain live political pressure points; the
tech slot is still anchored by Microsoft and the broader AI policy cycle.

The 2026-07-09 15:02 slot shifts the domestic feed toward the health-reform
split, doctor reactions, the Poznań anti-Ukrainian case and the Lubartów
hospital-oversight dispute, while IMGW keeps the alert layer on wind and
bursts. Abroad, Iran remains the top-risk item, but Ukraine Patriots and the
new UK-led deep precision strike initiative put NATO security back in focus;
technology now leans more clearly into AI regulation and Samsung's profit
signal.

The 2026-07-09 18:00 slot moves the domestic mix toward a formal Supreme
Court appointment, a local predator warning, a Warsaw crash, weather
interventions and the unchanged RPP line, while the world block stays
dominated by Iran, Ormuz, NATO and Ukraine. OpenAI's GPT-5.6 cycle is now the
clearest technology signal in the feed.

The 2026-07-09 21:02 slot shifts the domestic mix toward euro pressure, PAŻP
financing stress, Mogilno, Poznań and a fresh weather-alert bundle, while the
world block adds new CNN/BBC coverage on Iran, Ukrainian Patriots, a Greek
F-16 crash, a Chinese factory fire and the Sudan ICC probe. The tech block did
not add a distinct new signal in this run.

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
