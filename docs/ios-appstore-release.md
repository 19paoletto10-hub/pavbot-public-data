# Pavbot iOS App Store Release

Date: 2026-06-27

## Release Target

- App name: Pavbot
- Scheme: `PavbotViewer`
- Bundle ID: `com.paweltanski.pavbotviewer`
- Live Activity extension: `com.paweltanski.pavbotviewer.audioactivity`
- Apple Team ID: `SP774TZZU8`
- Marketing version: `2.0`
- Build number: dynamic, set by the Xcode build phase from `PAVBOT_BUILD_NUMBER`
  or the latest git commit timestamp.

## What Version 2.0 Contains

- Production connection URLs are fixed in the app and shown as read-only
  values in `Ustawienia`.
- Legacy custom Manifest URL and Notification server URL values are replaced
  by the production Pavbot defaults.
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
4. Confirm version `2.0` in target settings.
5. Use `Product -> Archive`.
6. In Organizer, choose `Distribute App`.
7. Choose `App Store Connect -> Upload`.
8. After processing, add the build to TestFlight in App Store Connect.

Use a unique UTC timestamp build number when archiving for App Store Connect:

```bash
BUILD_NUMBER="$(date -u +%Y%m%d%H%M)"
ARCHIVE_DATE="$(date +%Y-%m-%d)"
ARCHIVE_PATH="$HOME/Library/Developer/Xcode/Archives/$ARCHIVE_DATE/PavbotViewer-2.0-$BUILD_NUMBER.xcarchive"

PAVBOT_BUILD_NUMBER="$BUILD_NUMBER" xcodebuild archive \
  -project ios/PavbotViewer/PavbotViewer.xcodeproj \
  -scheme PavbotViewer \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE_PATH"
```

Open the completed archive in Xcode Organizer and upload through App Store Connect:

```bash
open -a /Users/promaczek/Downloads/Xcode.app "$ARCHIVE_PATH"
```

Submit to App Store review from App Store Connect after upload processing is complete.
