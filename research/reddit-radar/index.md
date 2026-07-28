# Topic Index: reddit-radar

## Current State

- Topic operates as a read-only Reddit humor radar built from live Safari review
  on public `old.reddit.com` listings and exact post pages.
- Current active public bundle is now
  `research/reddit-radar/data/2026-07-28-0608-reddit-radar.json`.
- Tuesday, July 28, 2026 06:08 CEST found exactly four fresh, public-safe
  survivors after filtering `2026-07-27-1809` and `2026-07-27-2208`, so the
  topic still rotated at the minimum contract threshold into a thinner morning
  set led by one flaky-pipeline dev card plus three everyday self-owns about a
  damaged car seat, a mistaken hair color, and a shattered PC side panel.
- The same 06:08 CEST audit also confirmed that origin/main already exposed the
  latest `2026-07-27-2208` public bundle before publication, so this slot is a
  normal fresh rotation and not a remote-state recovery publish.
- Monday, July 27, 2026 22:08 CEST found five fresh, public-safe survivors
  after filtering `2026-07-27-1209` and `2026-07-27-1809`, so the topic
  rotated again to a lighter late-night set led by two fresh meme cards, two
  gentler dev cards, and one packaging-annoyance everyday card.
- The same 22:08 CEST audit also found that `origin/main` still exposed the
  older `2026-07-27-0607` public bundle and did not yet contain the local
  `2026-07-27-1809` material update before publication, so this slot doubled
  as a remote-state catch-up.
- Monday, July 27, 2026 18:09 CEST found six fresh, public-safe survivors
  after filtering `2026-07-27-0607` and `2026-07-27-1209`, so the topic
  rotated away from the thin morning bundle to a fuller evening set led by
  comment-culture meta humor, three dev cards, and two everyday absurd cards.
- Monday, July 27, 2026 12:09 CEST live Safari audit did not clear the
  four-card threshold after filtering `2026-07-27-0607` and `2026-07-26-2208`,
  so that midday slot kept the active public bundle at `2026-07-27-0607`.
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
- A lighter bundle is still publishable when it clears four fresh survivors
  after the two-run freshness filter; this topic values rotation over sitting
  on an older, stronger winner bundle.
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
- Always verify `origin/main` itself before notifying downstream systems; local
  material updates can exist without becoming public if a publish step is
  missed or delayed.
- No Reddit social actions are ever allowed.
- Production notifier dispatch must stay behind successful `origin/main`
  verification and only happens for material updates.
