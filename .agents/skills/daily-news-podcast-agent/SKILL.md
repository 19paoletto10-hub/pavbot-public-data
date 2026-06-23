---
name: daily-news-podcast-agent
description: Use when Codex is asked to create a Polish Pavbot public-news podcast from the polska-swiat topic, especially for Poland, world affairs, politics, security, diplomacy, and major public events.
---

# Daily News Podcast Agent

This is a thin topic wrapper around `$daily-podcast-agent`.

Use `research/polska-swiat` as the default topic and apply a public-news
editorial profile:

- prioritize Poland, world affairs, politics, public institutions, security,
  diplomacy, conflicts, elections, public economy, and major social events;
- exclude gossip, clickbait, celebrity items, sports, investment/legal/medical
  advice, and unverified social-media claims;
- prefer public sources such as TVN24, WP, Onet, Interia, RMF24, Polsat News,
  Business Insider Polska, PAP when publicly available, BBC, Reuters/AP through
  public pages, The Guardian, Politico, Euronews, and official institution
  statements;
- choose 4-6 items with the strongest public importance for a Polish listener.

Then follow the shared workflow in `$daily-podcast-agent`:

- create `draft.md` before final `script.md`;
- verify claims against linked sources;
- write a spoken Polish script with full diacritics;
- write `sources.md` with used, checked-unused, and unavailable sources;
- render via `.agents/scripts/podcast/render-podcast-audio.sh`;
- keep rerendering/revising until `podcast.mp3` is 450-510 seconds;
- write `render.json` next to the MP3.
- create `brief.pdf` with the shared PDF renderer after audio metadata exists.
- publish the final topic output with
  `scripts/pavbot_commit_and_push_outputs.sh research/polska-swiat`.

Default output folder:

```text
research/polska-swiat/podcasts/YYYY-MM-DD/
```
