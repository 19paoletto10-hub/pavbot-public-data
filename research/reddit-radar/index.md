# Topic Index: reddit-radar

## Current State

- Topic operates as a read-only Reddit humor radar built from live Safari review
  on public `old.reddit.com` listings and exact post pages.
- Current active public bundle is now
  `research/reddit-radar/data/2026-07-26-2208-reddit-radar.json`.
- Sunday, July 26, 2026 12:08 CEST and 18:08 CEST both ended as
  `No material change`, but the 22:08 CEST Safari audit found five fresh,
  comment-verified survivors and rotated the public bundle away from the older
  06:09 set.

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
