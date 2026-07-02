# Topic Contract: reddit-radar

Status: Active

`research/reddit-radar` stores local audit artifacts for the Pavbot Reddit
Safari Humor Radar automation.

Allowed automation outputs:

- `data/YYYY-MM-DD-HHMM-reddit-radar-raw.json` - raw selected Reddit post
  context, comment snippets gathered from the logged-in Safari session, and
  local comment analysis status fields: `commentAnalysisStatus`,
  `commentAnalysisSource`, and `commentAnalysisNote`.
- `data/YYYY-MM-DD-HHMM-reddit-radar.json` - final public digest payload ready
  for `/v1/humor/digest`.
- `runs/YYYY-MM-DD-HHMM-reddit-radar.md` - Polish audit summary with the
  prepared post/comment analysis.

The automation may write only under this topic. It must not vote, comment,
share, submit forms, bypass login/CAPTCHA flows, or publish Reddit content.
It may publish the final digest only after each item is marked `reviewed` or
`no_safe_comments` from read-only Safari/Computer Use review.

Rotation rules:

- Keep at most 12 unique Reddit posts in the current radar.
- Each run adds newly found non-duplicate posts.
- When the radar is already full, replace up to 6 oldest posts with newly
  found posts and keep the remaining newest posts.
- Do not re-publish a post already used in a previous Reddit Radar output from
  the last 72 hours, even if it already rotated out of the current 12-item
  state.
- "Do not re-publish" means no repeated Reddit URL, and if the URL is missing,
  no repeated title, from runs stored in `research/reddit-radar/data/` within
  the last 72 hours.
- Only posts published on Reddit within the last 72 hours of the current run
  are eligible. If Safari/DOM does not expose a trustworthy publication time,
  skip the post as unverifiable.
