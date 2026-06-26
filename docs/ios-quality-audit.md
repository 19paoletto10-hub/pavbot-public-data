# iOS Quality Audit - Pavbot

Date: 2026-06-26

## Findings

- UI had mixed Polish and English copy in primary flows: Automations, Research, Settings, Diagnostics, artifact previews.
- Manifest auto-refresh could be started more than once by repeated lifecycle tasks.
- Jobs and daily weather stores silently kept cached data after refresh failures, so the user saw stale content without a clear reason.
- Artifact previews exposed raw technical errors and had weak recovery actions.
- Settings behaved like a developer form instead of a connection center for Manifest, notifications, weather and diagnostics.
- Research issue leads and article summaries were still vulnerable to hard truncation in the first screen, which weakened the editorial value of Tech News and Polska i Świat.
- Jobs and Research views did too much filtering and grouping directly in SwiftUI `body`, increasing the risk of unnecessary recomputation during refresh or search.
- Foreground refresh paths could trigger overlapping manifest/weather/humor reloads when the app returned from background.
- `Puls Dnia` needed local memory: without a persisted cache, a failed refresh
  could make recently fetched pulse news feel like they disappeared.
- Research still used a text search field in the main reading surface, where a
  dynamic audio control is more useful during podcast playback.
- Weather refresh had the plumbing for hourly backend updates but needed a
  clearer location-aware path and visible Wrocław fallback.

## Decisions

- Keep technical terms only where they are actual product concepts: APNs, GitHub raw URL, Manifest URL, TestFlight.
- Show cached data explicitly with a Polish banner when remote refresh fails.
- Use one shared user-facing error model for manifest, network, notifier, audio and preview errors.
- Use `PavbotLoadState` for screen/store load states where possible, so errors carry title, message, CTA, icon and tint instead of raw strings.
- Use `ReloadGate` for request deduplication and light throttling on manifest, weather and humor refresh paths.
- Keep Research leads complete in the premium hero. The UI should structure long text with spacing and signals, not cut the source insight.
- Move expensive Jobs/Research filtering into presentation snapshots before rendering cards.
- Keep the existing manifest and APNs payload schemas unchanged.
- Improve screens incrementally with shared SwiftUI primitives instead of a risky full visual rewrite.
- Keep `Puls Dnia` as a first-class tab backed by `pulseNewsData`, with local
  48-hour retention for unsaved runs and unlimited local storage for saved
  news.
- Replace the main Research search field with a global audio mini-player while
  keeping search in Jobs, technical file views and saved lists.
- Add local saved Research articles for the `Polska` and `Świat` sections,
  without changing the manifest or backend.
- Add system/light/dark appearance preference and use semantic system colors
  for the primary surfaces.
- Ship the next TestFlight/App Store candidate as marketing version `1.5` while
  preserving automatic `CFBundleVersion` generation.

## Regression Checklist

- Automations shows Polish dashboard copy, tiles, latest run and inline explanation bubble.
- Jobs shows the premium brief and a cache banner when JSON refresh fails but cached data exists.
- Jobs "Wszystkie oferty" keeps the same filter results after the presentation snapshot refactor.
- Research shows Tech News and Polska i Świat packages with Polish actions for Markdown, PDF, podcast brief and audio.
- Research "Wydanie dnia" shows the full moderated lead, not a hard-clipped summary with ellipsis.
- Research article cards and signal rows keep readable spacing and do not hide the main explanation behind aggressive line limits.
- Dzisiaj shows the latest weather report and clearly marks cached weather after failed refresh.
- Dzisiaj foreground refresh must not start parallel weather or humor requests.
- Settings acts as Centrum połączeń: Manifest, Powiadomienia, Pogoda and Diagnostyka are understandable without developer context.
- Artifact previews show Polish loading/error states, retry action and raw-link fallback.
- Diagnostics uses Polish issue titles while preserving APNs/GitHub technical names.
- Puls Dnia opens instantly from local cache when available, refreshes from the
  manifest in the background, and prunes unsaved runs after 48 hours.
- Saved pulse news remain available in `Zapisane` after the 48-hour history
  window.
- Saved Research articles can be added from article detail, opened from the
  Research toolbar and removed locally.
- The global audio mini-player appears for active MP3 playback and can pause,
  resume or close playback without leaving the current tab.
- Weather reports use current location when allowed and show a Wrocław fallback
  notice when location is unavailable.
- Appearance switching works for Auto/Jasny/Ciemny without relaunching.
- Dynamic Type should not clip primary labels, buttons remain at least 44 pt tappable, and badges keep readable contrast.

## Verification

- Targeted iOS tests for Polish user-facing errors, report copy, auto-refresh idempotence, `ReloadGate`, Research non-clipped lead and cache banners passed.
- Latest targeted Puls Dnia retention tests passed on `PavbotViewer`.
- Full project verification should include:
  - `xcodegen generate`
  - `xcodebuild test -project ios/PavbotViewer/PavbotViewer.xcodeproj -scheme PavbotViewer -destination 'platform=iOS Simulator,name=iPhone 17 Pro' CODE_SIGNING_ALLOWED=NO`
  - iPad/Mac-designed build on an iPad simulator
  - `scripts/verify-research-workspace.sh`
  - `.venv/bin/python -m pytest -q`

## Remaining Risk

- Some low-level Apple framework errors still originate as `localizedDescription`, but they now pass through `PavbotUserFacingError` before reaching visible UI.
- Backend and artifact schemas were intentionally not changed in this pass; if `/status` or manifest data is stale, the iOS app can explain the failure but cannot repair the server by itself.
- Large remote images in the humor feed use stable layout placeholders now, but a future image cache/downsampling layer would still be useful if Reddit media gets heavy.
