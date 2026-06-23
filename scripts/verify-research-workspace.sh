#!/usr/bin/env bash
set -euo pipefail

required_files=(
  "README.md"
  "AGENTS.md"
  "docs/architecture.md"
  "docs/sdlc.md"
  "docs/todo.md"
  "docs/how-to-use.md"
  "docs/connect-ios-app-to-your-repo.md"
  "docs/live-ios-notifications-macbook-cloudflare.md"
  "docs/live-ios-notifications-contabo.md"
  "docs/automation-operations.md"
  "backend/pavbot-notifier/Dockerfile"
  "backend/pavbot-notifier/docker-compose.yml"
  "backend/pavbot-notifier/.env.example"
  "backend/pavbot-notifier/cloudflare/config.example.yml"
  "backend/pavbot-notifier/launchd/com.pavbot.notifier.plist.example"
  "backend/pavbot-notifier/launchd/com.pavbot.cloudflared.plist.example"
  "backend/pavbot-notifier/scripts/install-macbook-launchd.sh"
  "backend/pavbot-notifier/requirements.txt"
  "backend/pavbot-notifier/pavbot_notifier/core.py"
  "backend/pavbot-notifier/pavbot_notifier/server.py"
  "backend/pavbot-notifier/pavbot_notifier/apns.py"
  "requirements.txt"
  "public/pavbot-manifest.json"
  "ios/PavbotViewer/project.yml"
  "ios/PavbotViewer/PavbotViewer.xcodeproj/project.pbxproj"
  "ios/PavbotViewer/PavbotViewer.xcodeproj/xcshareddata/xcschemes/PavbotViewer.xcscheme"
  "ios/PavbotViewer/PavbotViewer.xcodeproj/xcshareddata/xcschemes/PavbotViewerPush.xcscheme"
  "ios/PavbotViewer/Sources/PavbotViewerApp.swift"
  "ios/PavbotViewer/Sources/PavbotViewerPush.entitlements"
  "ios/PavbotViewer/Sources/Models/PavbotManifest.swift"
  "ios/PavbotViewer/Sources/Navigation/AppRouter.swift"
  "ios/PavbotViewer/Sources/Services/ArtifactNotificationService.swift"
  "ios/PavbotViewer/Sources/Services/ManifestDiagnostics.swift"
  "ios/PavbotViewer/Sources/Services/ManifestURLValidator.swift"
  "ios/PavbotViewer/Sources/Services/ManifestStore.swift"
  "ios/PavbotViewer/Sources/Views/PavbotDesign.swift"
  "ios/PavbotViewer/Sources/Views/ContentView.swift"
  "ios/PavbotViewer/Sources/Views/AutomationListView.swift"
  "ios/PavbotViewer/Sources/Views/ArtifactTimelineView.swift"
  "ios/PavbotViewer/Sources/Views/ArtifactDetailView.swift"
  "ios/PavbotViewer/Sources/Views/DiagnosticsView.swift"
  "ios/PavbotViewer/Sources/Views/SettingsView.swift"
  "ios/PavbotViewer/Tests/PavbotManifestTests.swift"
  "scripts/generate_pavbot_manifest.py"
  "scripts/pavbot_commit_and_push_outputs.sh"
  "scripts/render_research_pdf.py"
  "tests/test_generate_pavbot_manifest.py"
  "tests/test_pavbot_commit_and_push_outputs.py"
  "tests/test_render_research_pdf.py"
  "tests/test_render_mobile_brief_pdf.py"
  "integrations/openclaw/README.md"
  "integrations/openclaw/openclaw.sample.json5"
  "integrations/openclaw/workspace/AGENTS.md"
  "integrations/openclaw/workspace/SOUL.md"
  "integrations/openclaw/workspace/TOOLS.md"
  "integrations/openclaw/workspace/HEARTBEAT.md"
  ".agents/skills/daily-research-agent/SKILL.md"
  ".agents/skills/daily-podcast-agent/SKILL.md"
  ".agents/skills/daily-podcast-agent/agents/openai.yaml"
  ".agents/scripts/podcast/render-podcast-audio.sh"
  ".agents/scripts/podcast/download-local-tts-models.sh"
  ".agents/scripts/podcast/render_xtts.py"
  ".agents/scripts/podcast/editorial_lint.sh"
  ".agents/scripts/podcast/render-podcast-brief-pdf.py"
  "research/README.md"
  "research/templates/topic-template.md"
  "research/templates/run-report-template.md"
  "research/templates/index-template.md"
  "research/templates/backlog-template.md"
  "research/templates/proposal-template.md"
  "research/templates/new-topic-checklist.md"
  "research/codex-agent-automation/topic.md"
  "research/codex-agent-automation/index.md"
  "research/codex-agent-automation/backlog.md"
  "research/codex-agent-automation/runs/2026-06-17.md"
  "research/codex-agent-automation/automation-prompt.md"
  ".agents/skills/daily-tech-podcast-agent/SKILL.md"
  ".agents/skills/daily-tech-podcast-agent/agents/openai.yaml"
  ".agents/skills/daily-tech-podcast-agent/scripts/render-podcast-audio.sh"
  ".agents/skills/daily-news-podcast-agent/SKILL.md"
  ".agents/skills/daily-news-podcast-agent/agents/openai.yaml"
  ".agents/skills/daily-news-podcast-agent/scripts/render-podcast-audio.sh"
  "research/tech-news/topic.md"
  "research/tech-news/index.md"
  "research/tech-news/backlog.md"
  "research/tech-news/runs/.gitkeep"
  "research/tech-news/proposals/.gitkeep"
  "research/tech-news/podcasts/.gitkeep"
  "research/tech-news/pdfs/2026-06-18-tech-news.pdf"
  "research/tech-news/automation-research-prompt.md"
  "research/tech-news/automation-podcast-prompt.md"
  "research/polska-swiat/topic.md"
  "research/polska-swiat/index.md"
  "research/polska-swiat/backlog.md"
  "research/polska-swiat/runs/.gitkeep"
  "research/polska-swiat/proposals/.gitkeep"
  "research/polska-swiat/podcasts/.gitkeep"
  "research/polska-swiat/automation-research-prompt.md"
  "research/polska-swiat/automation-podcast-prompt.md"
  "research/llm-ai-jobs-wroclaw/topic.md"
  "research/llm-ai-jobs-wroclaw/index.md"
  "research/llm-ai-jobs-wroclaw/backlog.md"
  "research/llm-ai-jobs-wroclaw/runs/.gitkeep"
  "research/llm-ai-jobs-wroclaw/proposals/.gitkeep"
  "research/llm-ai-jobs-wroclaw/pdfs/.gitkeep"
  "research/llm-ai-jobs-wroclaw/automation-research-prompt.md"
  "research/aktualne-wydarzenia-mobile/topic.md"
  "research/aktualne-wydarzenia-mobile/index.md"
  "research/aktualne-wydarzenia-mobile/backlog.md"
  "research/aktualne-wydarzenia-mobile/runs/.gitkeep"
  "research/aktualne-wydarzenia-mobile/pdfs/.gitkeep"
  "research/aktualne-wydarzenia-mobile/podcasts/.gitkeep"
  "research/aktualne-wydarzenia-mobile/proposals/.gitkeep"
  "research/aktualne-wydarzenia-mobile/automation-prompt.md"
  "research/aktualne-wydarzenia-mobile/tools/render_mobile_brief_pdf.py"
  "research/aktualne-wydarzenia-mobile/tools/render_two_tts_variants.sh"
)

missing=0

for file in "${required_files[@]}"; do
  if [[ ! -f "$file" ]]; then
    printf 'missing: %s\n' "$file" >&2
    missing=1
  fi
done

if [[ $missing -ne 0 ]]; then
  exit 1
fi

grep -q '^name: daily-research-agent$' .agents/skills/daily-research-agent/SKILL.md
grep -q '^name: daily-podcast-agent$' .agents/skills/daily-podcast-agent/SKILL.md
grep -q '^name: daily-tech-podcast-agent$' .agents/skills/daily-tech-podcast-agent/SKILL.md
grep -q '^name: daily-news-podcast-agent$' .agents/skills/daily-news-podcast-agent/SKILL.md
grep -q '^name: pavbot-live-notifier$' .agents/skills/pavbot-live-notifier/SKILL.md
grep -q 'Cloudflare Tunnel' .agents/skills/pavbot-live-notifier/SKILL.md
grep -q 'PAVBOT_MANIFEST_URL' .agents/skills/pavbot-live-notifier/SKILL.md
python3 -m json.tool public/pavbot-manifest.json >/dev/null
grep -q '"schemaVersion": 1' public/pavbot-manifest.json
grep -q 'Pavbot Automation Manifest' public/pavbot-manifest.json
grep -q 'pavbot-llm-ai-jobs-wroclaw-research' public/pavbot-manifest.json
grep -q 'pavbot-aktualne-wydarzenia-mobile-10-15' public/pavbot-manifest.json
grep -q '^pdfplumber' requirements.txt
grep -q '^pytest' requirements.txt
grep -q '^reportlab' requirements.txt
grep -q 'PavbotViewer' ios/PavbotViewer/project.yml
grep -q 'struct PavbotViewerApp' ios/PavbotViewer/Sources/PavbotViewerApp.swift
grep -q 'PavbotRemoteNotificationAppDelegate' ios/PavbotViewer/Sources/PavbotViewerApp.swift
grep -q 'struct PavbotManifest' ios/PavbotViewer/Sources/Models/PavbotManifest.swift
grep -q 'resolvedURL' ios/PavbotViewer/Sources/Models/PavbotManifest.swift
grep -q 'newArtifacts' ios/PavbotViewer/Sources/Models/PavbotManifest.swift
grep -q 'newAutomations' ios/PavbotViewer/Sources/Models/PavbotManifest.swift
grep -q 'filteredArtifacts' ios/PavbotViewer/Sources/Models/PavbotManifest.swift
grep -q 'UNUserNotificationCenter' ios/PavbotViewer/Sources/Services/ArtifactNotificationService.swift
grep -q 'RemoteNotificationRegistrar' ios/PavbotViewer/Sources/Services/ArtifactNotificationService.swift
grep -q 'NotificationServerSettings' ios/PavbotViewer/Sources/Services/ArtifactNotificationService.swift
grep -q 'LiveNotificationOnboarding' ios/PavbotViewer/Sources/Services/ArtifactNotificationService.swift
grep -q 'RemoteNotificationPermission' ios/PavbotViewer/Sources/Services/ArtifactNotificationService.swift
grep -q 'ManifestDiagnostics' ios/PavbotViewer/Sources/Services/ManifestDiagnostics.swift
grep -q 'DiagnosticSeverity' ios/PavbotViewer/Sources/Services/ManifestDiagnostics.swift
grep -q 'ManifestURLValidator' ios/PavbotViewer/Sources/Services/ManifestURLValidator.swift
grep -q 'AppRouter' ios/PavbotViewer/Sources/Navigation/AppRouter.swift
grep -q 'searchable' ios/PavbotViewer/Sources/Views/ArtifactTimelineView.swift
grep -q 'DiagnosticsView' ios/PavbotViewer/Sources/Views/DiagnosticsView.swift
grep -q 'AppTab.diagnostics' ios/PavbotViewer/Sources/Views/ContentView.swift
grep -q 'public GitHub raw manifest URL' ios/PavbotViewer/Sources/Views/SettingsView.swift
grep -q 'Notification server URL' ios/PavbotViewer/Sources/Views/SettingsView.swift
grep -q 'notify.example.com/status' ios/PavbotViewer/Sources/Views/SettingsView.swift
grep -q 'Copy APNs device token' ios/PavbotViewer/Sources/Views/SettingsView.swift
grep -q 'RemoteNotificationDiagnostics' ios/PavbotViewer/Sources/Services/ArtifactNotificationService.swift
grep -q 'RemoteNotificationDiagnostics' ios/PavbotViewer/Tests/PavbotManifestTests.swift
grep -q 'Copy APNs device token' ios/PavbotViewer/Sources/Views/DiagnosticsView.swift
grep -q 'Live notifications' ios/PavbotViewer/Sources/Views/ContentView.swift
grep -q 'startAutoRefreshLoop' ios/PavbotViewer/Sources/Views/ContentView.swift
grep -q 'DEVELOPMENT_TEAM: SP774TZZU8' ios/PavbotViewer/project.yml
grep -q 'DEVELOPMENT_TEAM = SP774TZZU8' ios/PavbotViewer/PavbotViewer.xcodeproj/project.pbxproj
grep -q 'DebugPush' ios/PavbotViewer/PavbotViewer.xcodeproj/xcshareddata/xcschemes/PavbotViewerPush.xcscheme
grep -q 'ReleasePush' ios/PavbotViewer/PavbotViewer.xcodeproj/xcshareddata/xcschemes/PavbotViewerPush.xcscheme
grep -q 'DebugPush' ios/PavbotViewer/PavbotViewer.xcodeproj/project.pbxproj
grep -q 'ReleasePush' ios/PavbotViewer/PavbotViewer.xcodeproj/project.pbxproj
grep -q 'Sources/PavbotViewerPush.entitlements' ios/PavbotViewer/PavbotViewer.xcodeproj/project.pbxproj
! grep -q 'CODE_SIGN_ENTITLEMENTS = PavbotViewer.entitlements' ios/PavbotViewer/PavbotViewer.xcodeproj/project.pbxproj
grep -q 'generate_pavbot_manifest.py' docs/how-to-use.md
grep -q 'PAVBOT_MANIFEST_URL' docs/how-to-use.md
grep -q 'pavbot_commit_and_push_outputs.sh' docs/how-to-use.md
grep -q 'origin/main' docs/how-to-use.md
grep -q 'connect-ios-app-to-your-repo.md' README.md
grep -q 'connect-ios-app-to-your-repo.md' docs/how-to-use.md
grep -q 'PAVBOT_MANIFEST_URL' docs/connect-ios-app-to-your-repo.md
grep -q 'raw.githubusercontent.com' docs/connect-ios-app-to-your-repo.md
grep -q 'pavbot_commit_and_push_outputs.sh' docs/connect-ios-app-to-your-repo.md
grep -q 'Settings -> Manifest URL -> Save and reload' docs/connect-ios-app-to-your-repo.md
grep -q 'pavbot_commit_and_push_outputs.sh' docs/automation-operations.md
grep -q 'origin/main' docs/automation-operations.md
grep -q 'GitHub webhook' docs/live-ios-notifications-contabo.md
grep -q 'APNs' docs/live-ios-notifications-contabo.md
grep -q 'Cloudflare Tunnel' docs/live-ios-notifications-macbook-cloudflare.md
grep -q 'PAVBOT_PUBLIC_NOTIFIER_URL' docs/live-ios-notifications-macbook-cloudflare.md
grep -q 'pavbot_commit_and_push_outputs.sh' docs/live-ios-notifications-macbook-cloudflare.md
grep -q 'SP774TZZU8' docs/live-ios-notifications-macbook-cloudflare.md
grep -q 'Apple Push Notifications Console' docs/live-ios-notifications-macbook-cloudflare.md
grep -q 'launchd' docs/live-ios-notifications-macbook-cloudflare.md
grep -q 'PAVBOT_PUBLIC_NOTIFIER_URL' backend/pavbot-notifier/.env.example
grep -q 'APNS_TEAM_ID=SP774TZZU8' backend/pavbot-notifier/.env.example
grep -q 'pavbot-notifier' backend/pavbot-notifier/cloudflare/config.example.yml
grep -q 'uvicorn' backend/pavbot-notifier/Dockerfile
grep -q 'FastAPI' backend/pavbot-notifier/pavbot_notifier/server.py
grep -q '@app.get("/status")' backend/pavbot-notifier/pavbot_notifier/server.py
grep -q 'verify_github_signature' backend/pavbot-notifier/pavbot_notifier/core.py
grep -q 'notifier_status' backend/pavbot-notifier/pavbot_notifier/core.py
grep -q 'send_apns_change_notifications' backend/pavbot-notifier/pavbot_notifier/core.py
grep -q 'apnsAttempted' backend/pavbot-notifier/pavbot_notifier/server.py
grep -q 'APNSSender' backend/pavbot-notifier/pavbot_notifier/apns.py
! grep -R -q 'RLZ8X7S7V2' ios backend docs
grep -q 'pavbot-manifest.json' docs/architecture.md
grep -q 'PAVBOT_MANIFEST_URL' scripts/pavbot_commit_and_push_outputs.sh
grep -q 'generate_pavbot_manifest.py' scripts/pavbot_commit_and_push_outputs.sh
grep -q 'git fetch origin' scripts/pavbot_commit_and_push_outputs.sh
grep -q 'git push origin "HEAD:$target_branch"' scripts/pavbot_commit_and_push_outputs.sh
grep -q 'outside allowed publish paths' scripts/pavbot_commit_and_push_outputs.sh
grep -q 'pavbot_commit_and_push_outputs.sh' tests/test_pavbot_commit_and_push_outputs.py
grep -q '\$daily-podcast-agent' .agents/skills/daily-tech-podcast-agent/SKILL.md
grep -q '\$daily-podcast-agent' .agents/skills/daily-news-podcast-agent/SKILL.md
grep -q 'pavbot_commit_and_push_outputs.sh' .agents/skills/daily-research-agent/SKILL.md
grep -q 'pavbot_commit_and_push_outputs.sh' .agents/skills/daily-podcast-agent/SKILL.md
grep -q 'pavbot_commit_and_push_outputs.sh' .agents/skills/daily-tech-podcast-agent/SKILL.md
grep -q 'pavbot_commit_and_push_outputs.sh' .agents/skills/daily-news-podcast-agent/SKILL.md
grep -q 'pavbot_commit_and_push_outputs.sh' .agents/skills/pavbot-live-notifier/SKILL.md
grep -q '^# Topic Contract: codex-agent-automation$' research/codex-agent-automation/topic.md
grep -q '^# Topic Contract: tech-news$' research/tech-news/topic.md
grep -q '^# Topic Contract: polska-swiat$' research/polska-swiat/topic.md
grep -q '^# Topic Contract: llm-ai-jobs-wroclaw$' research/llm-ai-jobs-wroclaw/topic.md
grep -q '^# Topic Contract: aktualne-wydarzenia-mobile$' research/aktualne-wydarzenia-mobile/topic.md
grep -q '^Status: ' research/codex-agent-automation/runs/2026-06-17.md
grep -q 'Risk Gate' docs/architecture.md
grep -q '\$daily-research-agent' research/codex-agent-automation/automation-prompt.md
grep -q 'generate_pavbot_manifest.py' research/codex-agent-automation/automation-prompt.md
grep -q 'PAVBOT_MANIFEST_URL' research/codex-agent-automation/automation-prompt.md
grep -q 'pavbot_commit_and_push_outputs.sh research/codex-agent-automation' research/codex-agent-automation/automation-prompt.md
grep -q '\$daily-research-agent' research/tech-news/automation-research-prompt.md
grep -q 'generate_pavbot_manifest.py' research/tech-news/automation-research-prompt.md
grep -q 'PAVBOT_MANIFEST_URL' research/tech-news/automation-research-prompt.md
grep -q 'pavbot_commit_and_push_outputs.sh research/tech-news' research/tech-news/automation-research-prompt.md
grep -q 'render_research_pdf.py' research/tech-news/automation-research-prompt.md
grep -q 'render_research_pdf.py' .agents/skills/daily-research-agent/SKILL.md
test -s research/tech-news/pdfs/2026-06-18-tech-news.pdf
grep -q '\$daily-tech-podcast-agent' research/tech-news/automation-podcast-prompt.md
grep -q 'generate_pavbot_manifest.py' research/tech-news/automation-podcast-prompt.md
grep -q 'PAVBOT_MANIFEST_URL' research/tech-news/automation-podcast-prompt.md
grep -q 'pavbot_commit_and_push_outputs.sh research/tech-news' research/tech-news/automation-podcast-prompt.md
grep -q 'render-podcast-audio.sh' research/tech-news/automation-podcast-prompt.md
grep -q 'render.json' research/tech-news/automation-podcast-prompt.md
grep -q 'brief.pdf' research/tech-news/automation-podcast-prompt.md
grep -q 'PAVBOT_TTS_ENGINE' .agents/scripts/podcast/render-podcast-audio.sh
grep -q 'brief.pdf' .agents/skills/daily-podcast-agent/SKILL.md
grep -q 'reportlab' .agents/scripts/podcast/render-podcast-brief-pdf.py
grep -q 'coqui/XTTS-v2' .agents/scripts/podcast/download-local-tts-models.sh
grep -q 'pl_PL-gosia-medium' .agents/scripts/podcast/download-local-tts-models.sh
grep -q '.agents/scripts/podcast/render-podcast-audio.sh' .agents/skills/daily-tech-podcast-agent/scripts/render-podcast-audio.sh
grep -q '\$daily-research-agent' research/polska-swiat/automation-research-prompt.md
grep -q 'generate_pavbot_manifest.py' research/polska-swiat/automation-research-prompt.md
grep -q 'PAVBOT_MANIFEST_URL' research/polska-swiat/automation-research-prompt.md
grep -q 'pavbot_commit_and_push_outputs.sh research/polska-swiat' research/polska-swiat/automation-research-prompt.md
grep -q '\$daily-news-podcast-agent' research/polska-swiat/automation-podcast-prompt.md
grep -q 'generate_pavbot_manifest.py' research/polska-swiat/automation-podcast-prompt.md
grep -q 'PAVBOT_MANIFEST_URL' research/polska-swiat/automation-podcast-prompt.md
grep -q 'pavbot_commit_and_push_outputs.sh research/polska-swiat' research/polska-swiat/automation-podcast-prompt.md
grep -q 'pełnych polskich znaków' research/polska-swiat/automation-podcast-prompt.md
grep -q 'render.json' research/polska-swiat/automation-podcast-prompt.md
grep -q 'brief.pdf' research/polska-swiat/automation-podcast-prompt.md
grep -q 'pełnych polskich znaków' .agents/skills/daily-podcast-agent/SKILL.md
grep -q '.agents/scripts/podcast/render-podcast-audio.sh' .agents/skills/daily-news-podcast-agent/scripts/render-podcast-audio.sh
cmp -s .agents/skills/daily-tech-podcast-agent/scripts/render-podcast-audio.sh .agents/skills/daily-news-podcast-agent/scripts/render-podcast-audio.sh
grep -q 'workspaceAccess: "ro"' integrations/openclaw/openclaw.sample.json5
grep -q 'pavbot-observer' integrations/openclaw/openclaw.sample.json5
grep -q 'pavbot-llm-ai-jobs-wroclaw-research' docs/how-to-use.md
grep -q 'pavbot-llm-ai-jobs-wroclaw-research' docs/automation-operations.md
grep -q '\$daily-research-agent' research/llm-ai-jobs-wroclaw/automation-research-prompt.md
grep -q 'generate_pavbot_manifest.py' research/llm-ai-jobs-wroclaw/automation-research-prompt.md
grep -q 'PAVBOT_MANIFEST_URL' research/llm-ai-jobs-wroclaw/automation-research-prompt.md
grep -q 'pavbot_commit_and_push_outputs.sh research/llm-ai-jobs-wroclaw' research/llm-ai-jobs-wroclaw/automation-research-prompt.md
grep -q 'pavbot-aktualne-wydarzenia-mobile-10-15' docs/how-to-use.md
grep -q 'pavbot-aktualne-wydarzenia-mobile-10-15' docs/automation-operations.md
grep -q '\$daily-research-agent' research/aktualne-wydarzenia-mobile/automation-prompt.md
grep -q 'PAVBOT_MANIFEST_URL' research/aktualne-wydarzenia-mobile/automation-prompt.md
grep -q 'pavbot_commit_and_push_outputs.sh research/aktualne-wydarzenia-mobile' research/aktualne-wydarzenia-mobile/automation-prompt.md
grep -q 'render_mobile_brief_pdf.py' research/aktualne-wydarzenia-mobile/automation-prompt.md
grep -q 'render_two_tts_variants.sh' research/aktualne-wydarzenia-mobile/automation-prompt.md
grep -q 'female-piper' research/aktualne-wydarzenia-mobile/tools/render_two_tts_variants.sh
grep -q 'male-xtts' research/aktualne-wydarzenia-mobile/tools/render_two_tts_variants.sh
grep -q 'podcastAudioVariant' scripts/generate_pavbot_manifest.py

printf 'research workspace verified: %d required files present\n' "${#required_files[@]}"
