# Puls Dnia News Backlog

## Open

- After the manifest bootstrap, confirm the iOS app shows at least six pairs of
  cards from the newest `pulseNewsData`.
- Consider adding a future `pulseNewsImage` field only if the native card UI
  needs real thumbnails. Do not add scraped images without licensing review.
- Monitor whether BBC/CNN discovery regularly needs fallback confirmations from
  official sources because of access limits in the current runtime.
- `CNN World RSS` still looks stale in this slot; prefer TVN24/BBC discovery
  plus primary confirmations until the feed or page starts surfacing current
  2026 items again.
- Watch whether the Bangkok bar fire gets a formal casualty update or safety
  review from Thai authorities.
- Watch whether the IMGW storm-and-heat forecast turns into a formal regional
  warning for Poland.
- Watch whether the Apple/OpenAI lawsuit and Meta AI rollback produce official
  filings or product changes in the next slot.
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
- Watch whether ESA publishes a formal funding, staffing or launch timetable
  for the Warsaw centre.
- Watch whether police in the Bielsko-Biała bus-abuse case file charges or
  issue a formal clarification.
- Watch whether the Częstochowa collapse gets a casualty or cause update from
  rescuers or the building inspectorate.

## Done

- Production automation exists for `Pavbot Puls Dnia 3h` with the intended
  Europe/Warsaw cadence context.
- Public manifest now exposes `puls-dnia-news` artifacts as `pulseNewsData`,
  so the bootstrap blocker is resolved.
