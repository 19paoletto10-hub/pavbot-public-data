# Pavbot Puls Dnia News

## Purpose

`puls-dnia-news` is a fast news pulse for the iOS `Dzisiaj` tab. The output is
not a long article archive. It is a structured digest of many current topics
rendered as paired native cards in Pavbot.

## Scope

- Polish public affairs, politics, economy, security and alerts.
- World affairs, geopolitics, security, economy and major international events.
- Technology only when it is broadly relevant to the public news cycle.
- Primary discovery sources: TVN24, BBC and CNN.
- Prefer official or primary sources to confirm important claims.

## Cadence

Run every three hours during the day in `Europe/Warsaw`:

- 06:00
- 09:00
- 12:00
- 15:00
- 18:00
- 21:00

Each slot is a mandatory source check against TVN24, BBC and CNN. When a slot
finds new material articles relative to the latest published `pulseNewsData` on
`origin/main`, it must create a fresh timestamped report plus JSON and publish
them in the same cycle with the refreshed manifest. A newer local pulse-news
file than the latest remote manifest entry is a failed publication state, not a
successful run.

## Outputs

Each run must write:

- `research/puls-dnia-news/runs/YYYY-MM-DD-HHMM.md`
- `research/puls-dnia-news/data/YYYY-MM-DD-HHMM-pulse-news.json`

The JSON must validate with `scripts/validate_pulse_news_data.py` before
publishing. A valid run contains at least 12 news items and an even number of
items so the iOS app can render exactly two cards per carousel page.

## Publication Contract

The final step of every run is:

```bash
scripts/pavbot_commit_and_push_outputs.sh --isolated research/puls-dnia-news
```

This refreshes `public/pavbot-manifest.json`, commits only allowed outputs for
this topic plus the manifest, and pushes directly to `origin/main`.

If the run found new material articles, it is not complete until `origin/main`
shows the same newest `research/puls-dnia-news/data/*-pulse-news.json` path in
`public/pavbot-manifest.json` as `type: "pulseNewsData"`.
