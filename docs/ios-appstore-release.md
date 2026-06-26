# Pavbot iOS App Store Release

Date: 2026-06-26

## Release Target

- App name: Pavbot
- Scheme: `PavbotViewer`
- Bundle ID: `com.paweltanski.pavbotviewer`
- Live Activity extension: `com.paweltanski.pavbotviewer.audioactivity`
- Apple Team ID: `SP774TZZU8`
- Marketing version: `1.5`
- Build number: dynamic, set by the Xcode build phase from `PAVBOT_BUILD_NUMBER`
  or the latest git commit timestamp.

## What Version 1.5 Contains

- `Puls Dnia` is a top-level tab with paired news cards from
  `pulseNewsData`.
- `Puls Dnia` keeps a local 48-hour cache of fetched runs for smoother browsing.
- Saved pulse news stay locally in `Zapisane` without the 48-hour retention
  limit.
- Appearance can be switched between system, light and dark mode from
  `Ustawienia`.
- `Dzisiaj` can use the user's current location for weather after iOS location
  permission; Wrocław remains the fallback.
- Audio playback has a global mini-player with play/pause and close controls
  while moving between tabs.
- `Research` supports local saved articles for the `Polska` and `Świat`
  sections of `Polska i Świat`.
- `Dzisiaj`, `Jobs`, `Research`, and `Ustawienia` remain separate top-level
  areas.
- Live notifications still require the MacBook/Docker/Cloudflare/APNs notifier
  path to be online.

## Pre-Archive Checklist

1. Regenerate the Xcode project after `project.yml` changes:

   ```bash
   cd ios/PavbotViewer
   xcodegen generate
   ```

2. Run the simulator test suite:

   ```bash
   xcodebuild test \
     -project ios/PavbotViewer/PavbotViewer.xcodeproj \
     -scheme PavbotViewer \
     -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
     CODE_SIGNING_ALLOWED=NO
   ```

3. Run an iPad/Mac-designed build:

   ```bash
   xcodebuild build \
     -project ios/PavbotViewer/PavbotViewer.xcodeproj \
     -scheme PavbotViewer \
     -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' \
     CODE_SIGNING_ALLOWED=NO
   ```

4. Run repository verification:

   ```bash
   scripts/verify-research-workspace.sh
   .venv/bin/python -m pytest -q
   ```

5. Confirm Xcode Signing & Capabilities for `PavbotViewer`:
   - Team: `SP774TZZU8`
   - Push Notifications enabled for the App ID
   - Background Modes includes audio and remote notifications
   - Live Activities supported

## Archive And Upload

1. Open `ios/PavbotViewer/PavbotViewer.xcodeproj`.
2. Select scheme `PavbotViewer`.
3. Select `Any iOS Device (arm64)` or a physical iPhone.
4. Confirm version `1.5` in target settings.
5. Use `Product -> Archive`.
6. In Organizer, choose `Distribute App`.
7. Choose `App Store Connect -> Upload`.
8. After processing, add the build to TestFlight in App Store Connect.

If App Store Connect rejects the archive because the build number already
exists, set a newer explicit value before archiving:

```bash
export PAVBOT_BUILD_NUMBER=202606261930
```

Then archive again from the same shell-launched Xcode session or increment the
build number manually in Xcode for that archive.
