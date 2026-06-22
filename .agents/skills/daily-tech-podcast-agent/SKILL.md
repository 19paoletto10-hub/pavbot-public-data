---
name: daily-tech-podcast-agent
description: Use when Codex is asked to create a Polish Pavbot technology-news podcast from the tech-news topic, especially for AI, startup, product, regulation, and global technology news.
---

# Daily Tech Podcast Agent

This is a thin topic wrapper around `$daily-podcast-agent`.

Use `research/tech-news` as the default topic and apply a technology editorial
profile:

- prioritize AI, startups, product launches, platform changes, regulation,
  security, and major technology-business moves;
- prefer public sources such as TVN24, WP, Business Insider, Hacker News,
  Reddit, Product Hunt, official company blogs, and major technology outlets;
- do not require logged-in social media access;
- choose 4-6 items with the strongest technology relevance for a Polish
  listener.

Then follow the shared workflow in `$daily-podcast-agent`:

- create `draft.md` before final `script.md`;
- verify claims against linked sources;
- write a spoken Polish script with full diacritics;
- write `sources.md` with used, checked-unused, and unavailable sources;
- render via `.agents/scripts/podcast/render-podcast-audio.sh`;
- keep rerendering/revising until `podcast.mp3` is 450-510 seconds;
- write `render.json` next to the MP3.
- create `brief.pdf` with the shared PDF renderer after audio metadata exists.

Default output folder:

```text
research/tech-news/podcasts/YYYY-MM-DD/
```
