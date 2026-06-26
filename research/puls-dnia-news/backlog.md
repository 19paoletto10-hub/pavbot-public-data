# Puls Dnia News Backlog

## Open

- After the manifest bootstrap, confirm the iOS app shows at least six pairs of
  cards from the newest `pulseNewsData`.
- Consider adding a future `pulseNewsImage` field only if the native card UI
  needs real thumbnails. Do not add scraped images without licensing review.
- Monitor whether BBC/CNN discovery regularly needs fallback confirmations from
  official sources because of access limits in the current runtime.

## Done

- Production automation exists for `Pavbot Puls Dnia 3h` with the intended
  Europe/Warsaw cadence context.
- Public manifest now exposes `puls-dnia-news` artifacts as `pulseNewsData`,
  so the bootstrap blocker is resolved.
