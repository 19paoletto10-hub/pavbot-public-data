# Puls Dnia News Backlog

## Open

- After the manifest bootstrap, confirm the iOS app shows at least six pairs of
  cards from the newest `pulseNewsData`.
- Consider adding a future `pulseNewsImage` field only if the native card UI
  needs real thumbnails. Do not add scraped images without licensing review.
- Monitor whether BBC/CNN discovery regularly needs fallback confirmations from
  official sources because of access limits in the current runtime.
- `CNN World RSS` continues to fail intermittently; prefer
  `edition.cnn.com/world` discovery plus primary confirmations until the feed
  recovers.
- Watch whether the Chopin C3 scanner rollout gets a follow-up from the airport
  or queue-time reporting in the next few slots.
- Watch whether China export-control coverage picks up a fresh EU or industry
  response that would justify a separate card.
- Watch whether the AI-guided Tatry rescue gets a broader TOPR or tourism-
  safety follow-up.
- Watch whether the Stawki tram damage expands into wider Warsaw transport
  disruption.
- Watch whether the Qatar travel warning widens into a broader Middle East
  advisory or flight disruption.
- Watch whether CDC or WHO issue a follow-up on the Bundibugyo Ebola case in
  DRC.
- Watch whether the Korea Południowa heat alarm turns into broader official
  alerts in Europe or Poland.

## Done

- Production automation exists for `Pavbot Puls Dnia 3h` with the intended
  Europe/Warsaw cadence context.
- Public manifest now exposes `puls-dnia-news` artifacts as `pulseNewsData`,
  so the bootstrap blocker is resolved.
