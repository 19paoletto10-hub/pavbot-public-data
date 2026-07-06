# CloudKit Production Workflow

This file describes the current production workflow for PavbotViewer metadata,
CloudKit `Briefing` records, and APNs notifications.

Codex is the publisher. A completed automation run writes topic artifacts,
refreshes `public/pavbot-manifest.json`, verifies the exact files on
`origin/main`, and then publishes one ready CloudKit `Briefing` record for the
active topic. The iOS app reads CloudKit for briefing metadata and uses
`Briefing.manifestUrl` to load the published manifest.

## CloudKit Container

Production container:

```text
iCloud.com.paweltanski.pavbotviewer
```

The container ID must match:

- `PavbotConnectionDefaults.cloudKitContainerIdentifier`
- `ios/PavbotViewer/Sources/PavbotViewer.entitlements`
- `ios/PavbotViewer/project.yml`

The production app target uses:

- Bundle ID: `com.paweltanski.pavbotviewer`
- Team ID: `SP774TZZU8`
- APNs environment: `production`
- CloudKit environment: `Production`

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

Production records must use `status = "ready"` only after the matching manifest
and artifacts are verified on `origin/main`.

`briefingId` is the stable application identity used by both iOS and the Codex
publisher. `xcrun cktool create-record` generates the CloudKit record name, so
the publisher replaces existing records by querying/deleting on `briefingId`.
The app also fetches individual briefings by the `briefingId` field.

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

## iOS Subscription

The iOS app creates this public database subscription idempotently:

```text
briefings-ready-subscription
```

Configuration:

- Record Type: `Briefing`
- Predicate: `status == "ready"`
- Options: fires on record creation and record update
- Notification: visible APNs alert plus content-available/background refresh
- Localization keys: `PAVBOT_BRIEFING_NOTIFICATION_TITLE` and
  `PAVBOT_BRIEFING_NOTIFICATION_BODY`
- Desired keys: `briefingId`, `title`, `summary`, `manifestUrl`, `category`,
  `createdAt`

The push payload is both a user-visible alert and a refresh signal. The app
parses `CKQueryNotification.recordFields`, routes taps through `briefingId`,
fetches the latest `Briefing` records from CloudKit, and reloads the manifest
URL from `Briefing.manifestUrl`.

## Xcode Capabilities

Enable these capabilities for the PavbotViewer app target:

- iCloud
- CloudKit
- Push Notifications
- Background Modes -> Remote notifications

The project declares:

- `CloudKit.framework`
- `aps-environment`
- `com.apple.developer.icloud-container-environment`
- `com.apple.developer.icloud-container-identifiers`
- `com.apple.developer.icloud-services`

## Codex Publisher

Local CloudKit auth must stay outside the repo. Configure `cktool` locally:

```bash
xcrun cktool save-token
```

Publish a topic run with:

```bash
export PAVBOT_CLOUDKIT_CONTAINER_ID=iCloud.com.paweltanski.pavbotviewer
export PAVBOT_CLOUDKIT_ENVIRONMENT=production
export PAVBOT_CLOUDKIT_TEAM_ID=SP774TZZU8
scripts/pavbot_commit_and_push_outputs.sh --isolated research/<topic>
```

The script order is:

```text
prepare -> validate -> manifest -> CloudKit preflight -> commit/push -> remote verify -> CloudKit publish -> CloudKit verify
```

The CloudKit preflight is read-only. It checks local `cktool` authentication and
the target container before anything is committed or pushed. This prevents a
run from publishing a new remote manifest and then failing later because the
CloudKit token expired.

For normal automation publishing, `scripts/pavbot_commit_and_push_outputs.sh`
passes `--topic research/<topic>` to `scripts/publish_cloudkit_briefings.py`.
That creates or verifies only one ready `Briefing` record for the active
topic/run. Use `publish_cloudkit_briefings.py --all-topics` only for explicit
manual backfills or audits.

For local tests without `cktool`, use:

```bash
PAVBOT_CLOUDKIT_DRY_RUN=1 \
scripts/pavbot_commit_and_push_outputs.sh --isolated research/<topic>
```

## CloudKit Repair

Use repair mode when `origin/main` already contains the correct manifest and
topic artifacts, but CloudKit publication failed after the push:

```bash
export PAVBOT_CLOUDKIT_CONTAINER_ID=iCloud.com.paweltanski.pavbotviewer
export PAVBOT_CLOUDKIT_ENVIRONMENT=production
export PAVBOT_CLOUDKIT_TEAM_ID=SP774TZZU8
scripts/pavbot_commit_and_push_outputs.sh --cloudkit-only research/<topic>
```

Repair mode verifies `origin/main`, synchronizes the local manifest from the
published remote state, publishes the matching CloudKit `Briefing`, and verifies
that the record exists. It does not create a new commit.

## Development To Production

In CloudKit Console:

1. Create/update the Development schema.
2. Run the iOS app against Development and create a sample ready `Briefing`.
3. Verify the app receives the subscription push and refreshes the manifest.
4. Deploy schema changes to Production.
5. Run `scripts/publish_cloudkit_briefings.py verify` against Production.

## Push Notification Console

Use Apple's Push Notifications Console for manual APNs smoke tests and delivery
inspection:

- Documentation:
  <https://developer.apple.com/documentation/usernotifications/testing-notifications-using-the-push-notification-console>
- Sending requests to APNs:
  <https://developer.apple.com/documentation/usernotifications/sending-notification-requests-to-apns>
- Payload generation:
  <https://developer.apple.com/documentation/usernotifications/generating-a-remote-notification>

Production test values:

- Team: `SP774TZZU8`
- Bundle ID / APNs topic: `com.paweltanski.pavbotviewer`
- Environment: `Production`
- Push type: `alert`
- Priority: `High (10)`
- Expiration: attempt delivery once for smoke tests

Keep production device tokens, `.p8` keys, generated JWTs, and `cktool` tokens
out of the repository. The APNs console can validate a JWT and send a manual
test alert, but the production notification path is the CloudKit subscription
created by the iOS app.

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
