# CloudKit Migration

Pavbot no longer needs the Contabo notifier for iOS metadata, live briefing
pushes, Reddit Radar, or weather. Codex remains the publisher: it generates
topic artifacts, refreshes `public/pavbot-manifest.json`, commits and pushes to
`origin/main`, verifies the remote manifest, and then publishes CloudKit
metadata.

## CloudKit Container

Suggested container:

```text
iCloud.com.paweltanski.pavbotviewer
```

The container ID must match `PavbotConnectionDefaults.cloudKitContainerIdentifier`
and the iOS entitlements in `ios/PavbotViewer/Sources/PavbotViewer.entitlements`.

## Public Record Type: Briefing

Create `Briefing` in the public database with these fields:

- `briefingId`: String
- `title`: String
- `summary`: String
- `manifestUrl`: String
- `audioUrl`: String
- `imageUrl`: String
- `createdAt`: Date/Time
- `locale`: String
- `category`: String
- `status`: String
- `version`: Int(64)

Recommended query indexes:

- `status` queryable
- `createdAt` sortable
- `briefingId` queryable
- `category` queryable

Production records should use `status = "ready"` only after the matching
manifest and artifacts are verified on `origin/main`.

`briefingId` is the stable application identity used by both iOS and the Codex
publisher. `xcrun cktool create-record` generates the CloudKit record name, so
the publisher replaces existing records by querying/deleting on `briefingId`
and the app also fetches individual briefings by the `briefingId` field.

## Private Record Type: UserPreferences

Create `UserPreferences` in the private database with a stable record name:

```text
current-user-preferences
```

Fields:

- `preferredLocale`: String
- `city`: String
- `notificationHour`: Int(64)
- `enabledCategories`: List<String>
- `notificationsEnabled`: Int(64) or Bool, depending on CloudKit Console UI

Recommended query indexes:

- Record ID is enough for the current single-record model.

## Subscription

The iOS app creates this public database subscription idempotently:

```text
briefings-ready-subscription
```

Configuration:

- Record Type: `Briefing`
- Predicate: `status == "ready"`
- Options: fires on record creation and record update
- Notification: content-available/background refresh

The push payload is treated only as a signal. The app parses `CKNotification`,
then fetches the latest `Briefing` records from CloudKit and reloads the
manifest URL from `Briefing.manifestUrl`.

## Xcode Capabilities

Enable these capabilities for the PavbotViewer app target:

- iCloud
- CloudKit
- Push Notifications
- Background Modes -> Remote notifications

The project already declares:

- `CloudKit.framework`
- `aps-environment`
- `com.apple.developer.icloud-container-identifiers`
- `com.apple.developer.icloud-services`

## Codex Publisher

Local CloudKit auth must stay outside the repo. Configure `cktool` locally:

```bash
xcrun cktool save-token
```

Then publish with:

```bash
export PAVBOT_CLOUDKIT_CONTAINER_ID=iCloud.com.paweltanski.pavbotviewer
export PAVBOT_CLOUDKIT_ENVIRONMENT=production
export PAVBOT_CLOUDKIT_TEAM_ID=SP774TZZU8
scripts/pavbot_commit_and_push_outputs.sh --isolated research/<topic>
```

The script order is:

```text
prepare -> validate -> manifest -> commit/push -> remote verify -> CloudKit publish -> CloudKit verify
```

For local tests without `cktool`, use:

```bash
PAVBOT_CLOUDKIT_DRY_RUN=1 \
scripts/pavbot_commit_and_push_outputs.sh --isolated research/<topic>
```

## Development To Production

In CloudKit Console:

1. Create/update the Development schema.
2. Run the iOS app against Development and create a sample ready `Briefing`.
3. Verify the app receives the subscription push and refreshes the manifest.
4. Deploy schema changes to Production.
5. Run `scripts/publish_cloudkit_briefings.py verify` against Production.

## Legacy Notifier Removal

The Contabo notifier documentation and backend code remain in the repository
only as legacy reference. New iOS builds must not call:

- `https://notify.paweltanski.com`
- `/v1/app/defaults`
- `/v1/devices`
- `/v1/humor/latest`
- `/v1/weather/daily/*`

Weather now uses Open-Meteo directly from iOS with per-device location
preferences. Reddit Radar is published as an artifact and exposed through the
manifest/CloudKit briefing gate.

## Testing

Recommended checks:

```bash
python3 -m pytest tests/test_publish_cloudkit_briefings.py
python3 -m pytest tests/test_pavbot_commit_and_push_outputs.py
xcodebuild test \
  -project ios/PavbotViewer/PavbotViewer.xcodeproj \
  -scheme PavbotViewer \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:PavbotViewerTests/PavbotManifestTests
scripts/verify-research-workspace.sh
```
