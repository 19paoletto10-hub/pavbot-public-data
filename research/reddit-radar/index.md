# Topic Index: reddit-radar

## Current State

- Topic operates as a read-only Reddit humor radar built from live Safari review
  on public `old.reddit.com` listings and exact post pages.
- Current active public bundle is now
  `research/reddit-radar/data/2026-07-27-0607-reddit-radar.json`.
- Monday, July 27, 2026 12:09 CEST live Safari audit did not clear the
  four-card threshold after filtering `2026-07-27-0607` and `2026-07-26-2208`,
  so the active public bundle remains `2026-07-27-0607`.
- Monday, July 27, 2026 06:07 CEST found only a thin four-card survivor set,
  but that still satisfied the topic contract and rotated the public bundle
  away from the stronger 2026-07-26-2208 winner.

## Selection Rules

- Always filter out URLs that appeared in the two latest saved automation runs
  before comment-layer review.
- Prefer `r/memes`, `r/ProgrammerHumor`, and `r/mildlyinfuriating`; treat
  `r/facepalm` and `r/AskReddit` as lower-yield because they often drift into
  politics, heavy discourse, or broad discussion threads.
- Publish a new bundle only when at least 4 fresh cards survive final
  read-only Safari review with a compact, public-safe payoff.
- If fewer than 4 fresh survivors remain, keep the current bundle and record a
  short `No material change` audit.

## Working Heuristics

- Strong survivors usually keep one dominant joke in the first visible comments
  without turning into rant, politics, meta-discussion, or legal/support talk.
- Thin one-liner threads can still be useful as single cards, but they do not
  justify rotation without three similarly clean companions.
- A thinner fifth card is acceptable when the first four survivors are clearly
  fresh, public-safe, and the slot would otherwise meet the rotation contract.
- A four-card bundle is acceptable when fresh review quality clears the safety
  bar but the morning slot does not produce a convincing fifth survivor.
- Image-heavy or GIF-heavy comment sections that collapse into reaction images
  or fragmented references are weak candidates for the public digest.

## Operational Notes

- Safari Apple Events / DOM extraction is the reliable source-of-truth path for
  this topic. Computer Use has been intermittently flaky in prior runs, so lack
  of a stable Computer Use preflight is not by itself a blocker when Safari
  review works read-only.
- No Reddit social actions are ever allowed.
- Production notifier dispatch must stay behind successful `origin/main`
  verification and only happens for material updates.
