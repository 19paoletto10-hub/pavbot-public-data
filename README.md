# Pavbot Intelligence

Pavbot Intelligence is a local-first iOS and automation workspace for turning
Codex research runs into a polished mobile dashboard. The app reads a public
GitHub raw manifest, groups generated files by automation, and presents them as
native iOS experiences: Today, Pulse Day, Jobs, Research, audio/TTS, saved
articles, diagnostics, and live notification settings.

This repository contains the complete product workspace: the iOS app, the
optional APNs notifier backend, Codex automation prompts and skills, research
rendering scripts, generated manifest tooling, tests, and operational docs.

## Product Capabilities

- **Today** - weather, hourly temperature timeline, humor feed, daily context,
  and optional location-aware forecast.
- **Pulse Day** - 3-hour news pulse with paired swipeable cards, 48-hour local
  history, saved articles, and detailed source-backed summaries.
- **Jobs** - native LLM/AI job intelligence with structured `jobsData`,
  filters, history, sources, and PDF/Markdown fallbacks.
- **Research** - magazine-style Tech News, Poland/World, and Aktualne readers
  powered by structured JSON or Markdown fallback.
- **Audio** - MP3 playback, local iPhone TTS, rate controls, transcript support,
  mini-player, Now Playing integration, and Live Activity support.
- **Notifications** - optional APNs push flow through a local or hosted Pavbot
  notifier, GitHub webhook, and manifest diffing.
- **Diagnostics** - manifest freshness, cache state, notifier status, device
  token visibility, and connection defaults.
- **Accessibility** - system light/dark appearance, Dynamic Type, VoiceOver and
  Voice Control labels, reduced motion handling, contrast-aware UI, and
  transcript surfaces.

## Architecture

```text
Codex automations
  -> research/<topic>/ outputs
  -> public/pavbot-manifest.json
  -> GitHub raw manifest
  -> Pavbot iOS app

GitHub webhook
  -> backend/pavbot-notifier
  -> APNs
  -> iPhone notification routing
```

The iOS app remains a reader and organizer. Automations publish outputs to the
repository, regenerate the manifest, and push to `main`. The app refreshes the
manifest and renders native screens from structured artifacts such as
`jobsData`, `researchData`, `mobileNewsData`, and `pulseNewsData`.

## Repository Map

- `ios/PavbotViewer/` - SwiftUI iOS app, tests, XcodeGen project, Live Activity
  extension, app icons, services, and native screens.
- `backend/pavbot-notifier/` - Dockerized FastAPI notifier for GitHub webhooks,
  APNs pushes, weather reports, humor feed, and app defaults.
- `research/` - automation topics, prompts, run outputs, PDFs, podcast assets,
  structured data artifacts, topic indexes, and backlogs.
- `.agents/` - Codex skills and shared scripts used by scheduled automations.
- `scripts/` - manifest generation, publishing, PDF/data renderers, validators,
  and workspace verification.
- `tests/` - Python tests for manifest generation, publishing, renderers,
  validators, and notifier logic.
- `docs/` - setup guides, architecture, notifier operations, App Store release
  checklist, iOS quality audit, and user connection instructions.
- `public/pavbot-manifest.json` - generated manifest consumed by the app.

## iOS Development

Requirements:

- Xcode with iOS 17+ SDK support.
- XcodeGen installed locally.
- Apple Developer team configured for bundle id
  `com.paweltanski.pavbotviewer`.

Generate the project:

```bash
cd ios/PavbotViewer
xcodegen generate
```

Run simulator tests:

```bash
xcodebuild test \
  -project ios/PavbotViewer/PavbotViewer.xcodeproj \
  -scheme PavbotViewer \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  CODE_SIGNING_ALLOWED=NO
```

Archive for App Store Connect:

```bash
PAVBOT_BUILD_NUMBER="$(date -u +%Y%m%d%H%M)" \
xcodebuild archive \
  -project ios/PavbotViewer/PavbotViewer.xcodeproj \
  -scheme PavbotViewer \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "build/archives/PavbotViewer-${PAVBOT_BUILD_NUMBER}.xcarchive"
```

`PAVBOT_BUILD_NUMBER` is consumed by the Xcode build phase and written into the
app and Live Activity extension `CFBundleVersion`.

## Manifest Publishing

The app needs a public raw manifest URL, for example:

```text
https://raw.githubusercontent.com/<owner>/<repo>/<branch>/public/pavbot-manifest.json
```

Recommended automation environment:

```bash
export PAVBOT_MANIFEST_URL="https://raw.githubusercontent.com/<owner>/<repo>/<branch>/public/pavbot-manifest.json"
```

Publish a topic safely from a mixed development workspace:

```bash
scripts/pavbot_commit_and_push_outputs.sh --isolated research/<topic>
```

The isolated publisher copies only approved output paths for the active topic,
regenerates `public/pavbot-manifest.json`, commits the topic outputs and
manifest, then pushes to `origin/main`.

For a user-facing walkthrough of connecting an installed iOS app to a
Codex-backed repository, see `docs/connect-ios-app-to-your-repo.md`.

## Notifier Backend

The optional notifier runs locally or behind Cloudflare Tunnel and provides:

- GitHub webhook receiver.
- manifest diffing and one summary push per publication.
- APNs device registration and delivery diagnostics.
- daily weather and humor endpoints.
- `/v1/app/defaults` for app connection defaults.

Configure secrets locally through ignored files only:

```bash
cp backend/pavbot-notifier/.env.example backend/pavbot-notifier/.env
```

Never commit `.env`, APNs `.p8` keys, provisioning profiles, or other secrets.

Run locally:

```bash
docker compose -f backend/pavbot-notifier/docker-compose.yml up -d --build
curl http://localhost:8080/status
```

Expose through Cloudflare Tunnel for local/dev use:

```bash
cloudflared tunnel --url http://localhost:8080
```

For the production VPS variant, deploy only `backend/pavbot-notifier` to
Contabo and expose it through `https://notify.paweltanski.com` with the
container bound to `127.0.0.1:18082`. See
`docs/live-ios-notifications-contabo.md`.

## Automations

Each active automation must finish by publishing its own outputs together with
an updated public manifest:

```bash
PAVBOT_MANIFEST_URL="https://raw.githubusercontent.com/<owner>/<repo>/<branch>/public/pavbot-manifest.json" \
scripts/pavbot_commit_and_push_outputs.sh --isolated research/<topic>
```

Treat publication as a hard success gate. After every run that writes
app-visible artifacts, the publish script must regenerate
`public/pavbot-manifest.json`, commit the topic outputs plus the manifest, push
to `origin/main`, then verify the pushed manifest contains the current run
paths. If that remote verification fails, the run is partially published or
failed, not complete. Notifier-backed feeds such as Reddit Radar must publish
their audit artifacts/manifest before or alongside posting the digest to the
notifier so the iOS app and webhook do not depend on local-only files.

Current first-class topics include:

- `research/puls-dnia-news` - 3-hour Pulse Day news feed.
- `research/aktualne-wydarzenia-mobile` - mobile magazine, PDF, audio, and TTS
  source data.
- `research/llm-ai-jobs-wroclaw` - native Jobs screen data, PDF, and reports.
- `research/tech-news` - Tech News research, PDFs, podcast briefs, and data.
- `research/polska-swiat` - Poland/World research, PDFs, podcast briefs, and
  data.

## Verification

Run the workspace verifier before claiming the repository is ready:

```bash
scripts/verify-research-workspace.sh
```

Run Python tests:

```bash
.venv/bin/python -m pytest -q
```

Run iOS tests:

```bash
xcodebuild test \
  -project ios/PavbotViewer/PavbotViewer.xcodeproj \
  -scheme PavbotViewer \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  CODE_SIGNING_ALLOWED=NO
```

## Security Notes

- This repository should be private when it contains complete app source,
  operational scripts, or unpublished product work.
- Public GitHub raw manifest hosting is supported for v1 app data delivery.
- Private user repositories require a future OAuth/token or backend proxy
  model.
- Local secrets are intentionally ignored through `.gitignore`.
- Generated Xcode archives, IPAs, build folders, APNs keys, and provisioning
  profiles must not be committed.
