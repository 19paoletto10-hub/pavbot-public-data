# Puls Dnia News Backlog

## 2026-07-29 12:01

- Watch whether PiS publishes a formal club list or additional disciplinary responses.
- Watch for a post-meeting readout from Tusk and Zełenski with concrete security or aid language.
- Watch whether the fuel-price debate turns into a specific government or presidential move.
- Watch whether France, Portugal or Japan publish sharper casualty, closure or evacuation updates.
- Watch whether OpenAI, Telegram or regulators issue a direct follow-up on the AI and Durov stories.

## 2026-07-29 18:02

- Watch whether PiS turns the ultimatum into formal sanctions or a split.
- Watch whether Japan, France or Spain publish fresher casualty and evacuation counts.
- Watch whether Berlin police identify the suspect or file charges.
- Watch whether the OpenAI briefing yields a concrete safety-review timetable.

## 2026-07-29 09:01

- Watch whether IMGW i RCB podniosą upał i burze do twardszych komunikatów operacyjnych.
- Watch whether Grecja albo Francja poda kolejne ewakuacje, zamknięcia dróg lub aktualizacje pożarowe.
- Watch whether USGS, JMA or local authorities publish fresh post-quake casualty or damage counts for Japan.
- Watch whether the Asia AI selloff deepens or stabilizes after the latest TVN24 Biznes signal.
- Watch whether CNN's White House AI briefing turns into a concrete policy or market statement.

## 2026-07-29 06:01

- Watch whether IMGW i RCB przekują falę upałów w komunikaty operacyjne albo przerwy w transporcie.
- Watch whether France adds another evacuation, road closure or firefighting update around the heatwave.
- Watch whether Iran-USA, Japan or Boeing dostarczą dziś kolejny oficjalny follow-up.
- Watch whether the Washington AI briefing yields a direct company, regulator or market statement.


## Open

- After the manifest bootstrap, confirm the iOS app shows at least six pairs of
  cards from the newest `pulseNewsData`.
- Consider adding a future `pulseNewsImage` field only if the native card UI
  needs real thumbnails. Do not add scraped images without licensing review.
- Monitor whether BBC/CNN discovery regularly needs fallback confirmations from
  official sources because of access limits in the current runtime.
- `CNN World RSS` appears stale in the current runtime; prefer
  `edition.cnn.com/world` discovery plus primary confirmations until the feed
  recovers.

## Done

- Production automation exists for `Pavbot Puls Dnia 3h` with the intended
  Europe/Warsaw cadence context.
- Public manifest now exposes `puls-dnia-news` artifacts as `pulseNewsData`,
  so the bootstrap blocker is resolved.
