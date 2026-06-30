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
  "backend/pavbot-notifier/Start Pavbot Notifier.command"
  "backend/pavbot-notifier/Status Pavbot Notifier.command"
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
  "ios/PavbotViewer/Sources/PavbotViewerApp.swift"
  "ios/PavbotViewer/Sources/PavbotViewer.entitlements"
  "ios/PavbotViewer/Sources/Models/PavbotManifest.swift"
  "ios/PavbotViewer/Sources/Models/JobsReport.swift"
  "ios/PavbotViewer/Sources/Models/PulseNewsDigest.swift"
  "ios/PavbotViewer/Sources/Models/ResearchDataReport.swift"
  "ios/PavbotViewer/Sources/Models/ResearchIssuePresentation.swift"
  "ios/PavbotViewer/Sources/Models/ResearchNewsModels.swift"
  "ios/PavbotViewer/Sources/Models/TodayLiveTopics.swift"
  "ios/PavbotViewer/Sources/Navigation/AppRouter.swift"
  "ios/PavbotViewer/Sources/Services/AudioPlaybackService.swift"
  "ios/PavbotViewer/Sources/Services/ArtifactNotificationService.swift"
  "ios/PavbotViewer/Sources/Services/JobsDataService.swift"
  "ios/PavbotViewer/Sources/Services/JobsMarkdownParser.swift"
  "ios/PavbotViewer/Sources/Services/ManifestDiagnostics.swift"
  "ios/PavbotViewer/Sources/Services/ManifestURLValidator.swift"
  "ios/PavbotViewer/Sources/Services/ManifestStore.swift"
  "ios/PavbotViewer/Sources/Services/PavbotConnectionDefaults.swift"
  "ios/PavbotViewer/Sources/Services/PavbotAudioActivityAttributes.swift"
  "ios/PavbotViewer/Sources/Services/PulseNewsService.swift"
  "ios/PavbotViewer/Sources/Services/TodayLiveTopicsService.swift"
  "ios/PavbotViewer/Sources/Models/TopicReportPackage.swift"
  "ios/PavbotViewer/Sources/Views/PavbotDesign.swift"
  "ios/PavbotViewer/Sources/Views/ContentView.swift"
  "ios/PavbotViewer/Sources/Views/AutomationListView.swift"
  "ios/PavbotViewer/Sources/Views/ArtifactTimelineView.swift"
  "ios/PavbotViewer/Sources/Views/ArtifactDetailView.swift"
  "ios/PavbotViewer/Sources/Views/JobsView.swift"
  "ios/PavbotViewer/Sources/Views/ReportPackageViews.swift"
  "ios/PavbotViewer/Sources/Views/TodayLiveTopicsView.swift"
  "ios/PavbotViewer/Sources/Views/DiagnosticsView.swift"
  "ios/PavbotViewer/Sources/Views/SettingsView.swift"
  "ios/PavbotViewer/AudioActivityExtension/Info.plist"
  "ios/PavbotViewer/AudioActivityExtension/PavbotAudioActivityWidget.swift"
  "ios/PavbotViewer/Tests/PavbotManifestTests.swift"
  "scripts/generate_pavbot_manifest.py"
  "scripts/pavbot_commit_and_push_outputs.sh"
  "scripts/pavbot_publication_contract.py"
  "scripts/pavbot_pdf_theme.py"
  "scripts/render_mobile_news_data.py"
  "scripts/render_research_pdf.py"
  "scripts/render_research_data.py"
  "scripts/validate_research_data.py"
  "scripts/validate_jobs_data.py"
  "scripts/validate_pulse_news_data.py"
  "tests/test_generate_pavbot_manifest.py"
  "tests/test_pavbot_commit_and_push_outputs.py"
  "tests/test_validate_jobs_data.py"
  "tests/test_validate_pulse_news_data.py"
  "tests/test_render_research_data.py"
  "tests/test_render_research_pdf.py"
  "tests/test_render_jobs_data.py"
  "tests/test_render_mobile_brief_pdf.py"
  "tests/test_render_mobile_newspaper_pdf.py"
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
  "research/llm-ai-jobs-wroclaw/data/.gitkeep"
  "research/llm-ai-jobs-wroclaw/proposals/.gitkeep"
  "research/llm-ai-jobs-wroclaw/pdfs/.gitkeep"
  "research/llm-ai-jobs-wroclaw/tools/render_jobs_data.py"
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
  "research/aktualne-wydarzenia-mobile/tools/render_mobile_newspaper_pdf.py"
  "research/aktualne-wydarzenia-mobile/tools/render_two_tts_variants.sh"
  "research/puls-dnia-news/topic.md"
  "research/puls-dnia-news/index.md"
  "research/puls-dnia-news/backlog.md"
  "research/puls-dnia-news/runs/.gitkeep"
  "research/puls-dnia-news/data/.gitkeep"
  "research/puls-dnia-news/proposals/.gitkeep"
  "research/puls-dnia-news/automation-prompt.md"
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
grep -q 'pavbot-aktualne-wydarzenia-mobile-19-33' public/pavbot-manifest.json
grep -q 'pavbot-tech-research-19-33' public/pavbot-manifest.json
grep -q 'pavbot-polska-wiat-research-19-33' public/pavbot-manifest.json
grep -q 'pavbot-puls-dnia-news-3h' public/pavbot-manifest.json
grep -q 'researchAudio' public/pavbot-manifest.json
grep -q 'YYYY-MM-DD-HHMM-mobile-brief.pdf' public/pavbot-manifest.json
grep -q '^pdfplumber' requirements.txt
grep -q '^pytest' requirements.txt
grep -q '^reportlab' requirements.txt
grep -q 'PavbotViewer' ios/PavbotViewer/project.yml
grep -q 'PavbotAudioActivityExtension' ios/PavbotViewer/project.yml
grep -q 'MediaPlayer.framework' ios/PavbotViewer/project.yml
grep -q 'ActivityKit.framework' ios/PavbotViewer/project.yml
grep -q 'struct PavbotViewerApp' ios/PavbotViewer/Sources/PavbotViewerApp.swift
grep -q 'AudioPlaybackService' ios/PavbotViewer/Sources/PavbotViewerApp.swift
grep -q 'UIBackgroundModes' ios/PavbotViewer/Sources/Info.plist
grep -q 'NSSupportsLiveActivities' ios/PavbotViewer/Sources/Info.plist
grep -q 'pavbot' ios/PavbotViewer/Sources/Info.plist
grep -q 'MPNowPlayingInfoCenter' ios/PavbotViewer/Sources/Services/AudioPlaybackService.swift
grep -q 'MPRemoteCommandCenter' ios/PavbotViewer/Sources/Services/AudioPlaybackService.swift
grep -q 'AVAudioSession' ios/PavbotViewer/Sources/Services/AudioPlaybackService.swift
grep -q 'PavbotAudioActivityAttributes' ios/PavbotViewer/Sources/Services/AudioPlaybackService.swift
grep -q 'ActivityConfiguration' ios/PavbotViewer/AudioActivityExtension/PavbotAudioActivityWidget.swift
grep -q 'DynamicIsland' ios/PavbotViewer/AudioActivityExtension/PavbotAudioActivityWidget.swift
grep -q 'NSSupportsLiveActivities' ios/PavbotViewer/AudioActivityExtension/Info.plist
grep -q 'researchAudio' ios/PavbotViewer/Sources/Models/PavbotManifest.swift
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
grep -q 'PavbotConnectionDefaults' ios/PavbotViewer/Sources/Services/PavbotConnectionDefaults.swift
grep -q 'manifestURLString = "https://raw.githubusercontent.com/19paoletto10-hub/pavbot-public-data/main/public/pavbot-manifest.json"' ios/PavbotViewer/Sources/Services/PavbotConnectionDefaults.swift
grep -q 'notificationServerURLString = "https://notify.paweltanski.com"' ios/PavbotViewer/Sources/Services/PavbotConnectionDefaults.swift
grep -q 'statusURLString = "https://notify.paweltanski.com/status"' ios/PavbotViewer/Sources/Services/PavbotConnectionDefaults.swift
grep -q 'ManifestDiagnostics' ios/PavbotViewer/Sources/Services/ManifestDiagnostics.swift
grep -q 'DiagnosticSeverity' ios/PavbotViewer/Sources/Services/ManifestDiagnostics.swift
grep -q 'ManifestURLValidator' ios/PavbotViewer/Sources/Services/ManifestURLValidator.swift
grep -q 'AppRouter' ios/PavbotViewer/Sources/Navigation/AppRouter.swift
grep -q 'case jobs' ios/PavbotViewer/Sources/Navigation/AppRouter.swift
grep -q 'case research' ios/PavbotViewer/Sources/Navigation/AppRouter.swift
grep -q 'selectedResearchTopic' ios/PavbotViewer/Sources/Navigation/AppRouter.swift
grep -q 'openReportRoute' ios/PavbotViewer/Sources/Navigation/AppRouter.swift
grep -q 'ReportTopicKind' ios/PavbotViewer/Sources/Models/TopicReportPackage.swift
grep -q 'TopicReportPackage' ios/PavbotViewer/Sources/Models/TopicReportPackage.swift
grep -q 'researchDataArtifact' ios/PavbotViewer/Sources/Models/TopicReportPackage.swift
grep -q 'struct JobsReport' ios/PavbotViewer/Sources/Models/JobsReport.swift
grep -q 'struct JobOpportunity' ios/PavbotViewer/Sources/Models/JobsReport.swift
grep -q 'struct ResearchDataReport' ios/PavbotViewer/Sources/Models/ResearchDataReport.swift
grep -q 'whatHappened' ios/PavbotViewer/Sources/Models/ResearchDataReport.swift
grep -q 'whyItMatters' ios/PavbotViewer/Sources/Models/ResearchDataReport.swift
grep -q 'deeperAnalysis' ios/PavbotViewer/Sources/Models/ResearchDataReport.swift
grep -q 'case researchData' ios/PavbotViewer/Sources/Models/PavbotManifest.swift
grep -q 'JobsMarkdownParser' ios/PavbotViewer/Sources/Services/JobsMarkdownParser.swift
grep -q 'final class JobsStore' ios/PavbotViewer/Sources/Services/JobsDataService.swift
grep -q 'ResearchDataReport' ios/PavbotViewer/Sources/Services/ResearchNewsService.swift
grep -q 'searchable' ios/PavbotViewer/Sources/Views/ArtifactTimelineView.swift
grep -q 'DiagnosticsView' ios/PavbotViewer/Sources/Views/DiagnosticsView.swift
grep -q 'JobsView' ios/PavbotViewer/Sources/Views/ContentView.swift
grep -q 'ResearchView' ios/PavbotViewer/Sources/Views/ContentView.swift
grep -q 'Label("Jobs"' ios/PavbotViewer/Sources/Views/ContentView.swift
grep -q 'Label("Research"' ios/PavbotViewer/Sources/Views/ContentView.swift
grep -q 'ArtifactTimelineView' ios/PavbotViewer/Sources/Views/SettingsView.swift
grep -q 'DiagnosticsView' ios/PavbotViewer/Sources/Views/SettingsView.swift
grep -q 'struct JobsView' ios/PavbotViewer/Sources/Views/JobsView.swift
grep -q 'struct ResearchView' ios/PavbotViewer/Sources/Views/ReportPackageViews.swift
grep -q 'Połączenia Pavbot' ios/PavbotViewer/Sources/Views/SettingsView.swift
grep -q 'Serwer powiadomień' ios/PavbotViewer/Sources/Views/SettingsView.swift
grep -q 'Pavbot używa produkcyjnych adresów połączeń' ios/PavbotViewer/Sources/Views/SettingsView.swift
grep -q 'PavbotConnectionDefaults.statusURL' ios/PavbotViewer/Sources/Views/SettingsView.swift
grep -q 'Kopiuj token APNs' ios/PavbotViewer/Sources/Views/SettingsView.swift
grep -q 'RemoteNotificationDiagnostics' ios/PavbotViewer/Sources/Services/ArtifactNotificationService.swift
grep -q 'RemoteNotificationDiagnostics' ios/PavbotViewer/Tests/PavbotManifestTests.swift
grep -q 'wait_for_public_artifacts_ready' backend/pavbot-notifier/pavbot_notifier/server.py
grep -q 'lastPublicReadiness' backend/pavbot-notifier/pavbot_notifier/core.py
grep -q 'public raw' docs/live-ios-notifications-macbook-cloudflare.md
grep -q 'publiczny raw' research/puls-dnia-news/automation-prompt.md
grep -q 'Kopiuj token APNs' ios/PavbotViewer/Sources/Views/DiagnosticsView.swift
grep -q 'Powiadomienia live' ios/PavbotViewer/Sources/Views/ContentView.swift
grep -q 'startAutoRefreshLoop' ios/PavbotViewer/Sources/Views/ContentView.swift
grep -q 'DEVELOPMENT_TEAM: SP774TZZU8' ios/PavbotViewer/project.yml
grep -q 'DEVELOPMENT_TEAM = SP774TZZU8' ios/PavbotViewer/PavbotViewer.xcodeproj/project.pbxproj
grep -q 'CODE_SIGN_ENTITLEMENTS = Sources/PavbotViewer.entitlements' ios/PavbotViewer/PavbotViewer.xcodeproj/project.pbxproj
grep -q 'APS_ENVIRONMENT = development;' ios/PavbotViewer/PavbotViewer.xcodeproj/project.pbxproj
grep -q 'APS_ENVIRONMENT = production;' ios/PavbotViewer/PavbotViewer.xcodeproj/project.pbxproj
grep -q 'aps-environment' ios/PavbotViewer/Sources/PavbotViewer.entitlements
grep -q '$(APS_ENVIRONMENT)' ios/PavbotViewer/Sources/PavbotViewer.entitlements
grep -q 'postGenCommand: rm -f PavbotViewer.xcodeproj/xcshareddata/xcschemes/PavbotAudioActivityExtension.xcscheme' ios/PavbotViewer/project.yml
grep -q 'buildConfiguration = "Debug"' ios/PavbotViewer/PavbotViewer.xcodeproj/xcshareddata/xcschemes/PavbotViewer.xcscheme
grep -q 'buildConfiguration = "Release"' ios/PavbotViewer/PavbotViewer.xcodeproj/xcshareddata/xcschemes/PavbotViewer.xcscheme
! grep -q 'PavbotViewerPush' ios/PavbotViewer/project.yml
! grep -q 'DebugPush' ios/PavbotViewer/project.yml
! grep -q 'ReleasePush' ios/PavbotViewer/project.yml
! grep -q 'PavbotViewerPush' ios/PavbotViewer/PavbotViewer.xcodeproj/project.pbxproj
! grep -q 'DebugPush' ios/PavbotViewer/PavbotViewer.xcodeproj/project.pbxproj
! grep -q 'ReleasePush' ios/PavbotViewer/PavbotViewer.xcodeproj/project.pbxproj
! test -f ios/PavbotViewer/PavbotViewer.xcodeproj/xcshareddata/xcschemes/PavbotViewerPush.xcscheme
! test -f ios/PavbotViewer/PavbotViewer.xcodeproj/xcshareddata/xcschemes/PavbotAudioActivityExtension.xcscheme
! test -f ios/PavbotViewer/Sources/PavbotViewerPush.entitlements
grep -q 'generate_pavbot_manifest.py' docs/how-to-use.md
grep -q 'PAVBOT_MANIFEST_URL' docs/how-to-use.md
grep -q 'pavbot_commit_and_push_outputs.sh' docs/how-to-use.md
grep -q 'Kind: `researchAudio`' docs/how-to-use.md
grep -F -q 'RUN_STAMP=$(TZ=Europe/Warsaw date +%Y-%m-%d-%H%M)' docs/how-to-use.md
grep -q 'runs/YYYY-MM-DD-HHMM.md' docs/how-to-use.md
grep -q 'pdfs/YYYY-MM-DD-HHMM-newspaper.pdf' docs/how-to-use.md
grep -q 'podcasts/YYYY-MM-DD-HHMM/' docs/how-to-use.md
grep -q 'origin/main' docs/how-to-use.md
grep -q 'Live Activity/Dynamic Island' docs/how-to-use.md
grep -q 'researchData' scripts/generate_pavbot_manifest.py
grep -q 'validate_research_data.py' scripts/pavbot_commit_and_push_outputs.sh
grep -q 'render_research_data.py' research/tech-news/automation-research-prompt.md
grep -q -- '--require-app-articles' research/tech-news/automation-research-prompt.md
grep -q 'validate_research_data.py' research/tech-news/automation-research-prompt.md
grep -q 'research/tech-news/data/' research/tech-news/automation-research-prompt.md
grep -q 'render_research_data.py' research/polska-swiat/automation-research-prompt.md
grep -q -- '--require-app-articles' research/polska-swiat/automation-research-prompt.md
grep -q 'validate_research_data.py' research/polska-swiat/automation-research-prompt.md
grep -q 'research/polska-swiat/data/' research/polska-swiat/automation-research-prompt.md
grep -q 'connect-ios-app-to-your-repo.md' README.md
grep -q 'connect-ios-app-to-your-repo.md' docs/how-to-use.md
grep -q 'PAVBOT_MANIFEST_URL' docs/connect-ios-app-to-your-repo.md
grep -q 'raw.githubusercontent.com' docs/connect-ios-app-to-your-repo.md
grep -q 'pavbot_commit_and_push_outputs.sh' docs/connect-ios-app-to-your-repo.md
grep -q 'Settings -> Domyślne połączenia' docs/connect-ios-app-to-your-repo.md
grep -q 'pavbot_commit_and_push_outputs.sh' docs/automation-operations.md
grep -q 'origin/main' docs/automation-operations.md
grep -q 'GitHub webhook' docs/live-ios-notifications-contabo.md
grep -q 'APNs' docs/live-ios-notifications-contabo.md
grep -q 'Cloudflare Tunnel' docs/live-ios-notifications-macbook-cloudflare.md
grep -q 'PAVBOT_PUBLIC_NOTIFIER_URL' docs/live-ios-notifications-macbook-cloudflare.md
grep -q 'pavbot_commit_and_push_outputs.sh' docs/live-ios-notifications-macbook-cloudflare.md
grep -q 'SP774TZZU8' docs/live-ios-notifications-macbook-cloudflare.md
grep -q 'Closed-App Delivery' docs/live-ios-notifications-macbook-cloudflare.md
grep -q 'lastApnsDelivery' docs/live-ios-notifications-macbook-cloudflare.md
grep -q 'Apple Push Notifications Console' docs/live-ios-notifications-macbook-cloudflare.md
grep -q 'launchd' docs/live-ios-notifications-macbook-cloudflare.md
grep -q 'Start Pavbot Notifier.command' docs/live-ios-notifications-macbook-cloudflare.md
grep -q 'PAVBOT_PUBLIC_NOTIFIER_URL' backend/pavbot-notifier/.env.example
grep -q 'APNS_TEAM_ID=SP774TZZU8' backend/pavbot-notifier/.env.example
grep -q 'docker compose up -d --build' "backend/pavbot-notifier/Start Pavbot Notifier.command"
grep -q 'http://localhost:8080/status' "backend/pavbot-notifier/Status Pavbot Notifier.command"
grep -q 'pavbot-notifier' backend/pavbot-notifier/cloudflare/config.example.yml
grep -q 'uvicorn' backend/pavbot-notifier/Dockerfile
grep -q 'FastAPI' backend/pavbot-notifier/pavbot_notifier/server.py
grep -q '@app.get("/status")' backend/pavbot-notifier/pavbot_notifier/server.py
grep -q 'verify_github_signature' backend/pavbot-notifier/pavbot_notifier/core.py
grep -q 'notifier_status' backend/pavbot-notifier/pavbot_notifier/core.py
grep -q 'send_apns_change_notifications' backend/pavbot-notifier/pavbot_notifier/core.py
grep -q 'lastApnsDelivery' backend/pavbot-notifier/pavbot_notifier/core.py
grep -q 'last-device-registration.json' backend/pavbot-notifier/pavbot_notifier/server.py
grep -q 'apnsAttempted' backend/pavbot-notifier/pavbot_notifier/server.py
grep -q 'APNSSender' backend/pavbot-notifier/pavbot_notifier/apns.py
grep -q 'APNSConfigurationError' backend/pavbot-notifier/pavbot_notifier/apns.py
! grep -R -q 'RLZ8X7S7V2' ios backend docs
grep -q 'pavbot-manifest.json' docs/architecture.md
grep -q 'PAVBOT_MANIFEST_URL' scripts/pavbot_commit_and_push_outputs.sh
grep -q 'generate_pavbot_manifest.py' scripts/pavbot_commit_and_push_outputs.sh
grep -q -- '--isolated' scripts/pavbot_commit_and_push_outputs.sh
grep -q -- '--force-manifest' scripts/pavbot_commit_and_push_outputs.sh
grep -q 'git worktree add --detach' scripts/pavbot_commit_and_push_outputs.sh
grep -q 'copy_publishable_outputs_to_worktree' scripts/pavbot_commit_and_push_outputs.sh
grep -q 'topic_path/runs' scripts/pavbot_commit_and_push_outputs.sh
grep -q 'topic_path/pdfs' scripts/pavbot_commit_and_push_outputs.sh
grep -q 'topic_path/data' scripts/pavbot_commit_and_push_outputs.sh
grep -q 'topic_path/podcasts' scripts/pavbot_commit_and_push_outputs.sh
grep -q 'validate_jobs_data.py' scripts/pavbot_commit_and_push_outputs.sh
grep -q 'validate_pulse_news_data.py' scripts/pavbot_commit_and_push_outputs.sh
grep -q 'git fetch origin' scripts/pavbot_commit_and_push_outputs.sh
grep -q 'git push origin "HEAD:$target_branch"' scripts/pavbot_commit_and_push_outputs.sh
grep -q 'outside allowed publish paths' scripts/pavbot_commit_and_push_outputs.sh
grep -q 'pavbot_commit_and_push_outputs.sh' tests/test_pavbot_commit_and_push_outputs.py
grep -q 'isolated=True' tests/test_pavbot_commit_and_push_outputs.py
grep -q 'force_manifest=True' tests/test_pavbot_commit_and_push_outputs.py
grep -q 'tools/helper.sh' tests/test_pavbot_commit_and_push_outputs.py
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
grep -q '^# Pavbot Puls Dnia News$' research/puls-dnia-news/topic.md
grep -q '^Status: ' research/codex-agent-automation/runs/2026-06-17.md
grep -q 'Risk Gate' docs/architecture.md
grep -q '\$daily-research-agent' research/codex-agent-automation/automation-prompt.md
grep -q 'generate_pavbot_manifest.py' research/codex-agent-automation/automation-prompt.md
grep -q 'PAVBOT_MANIFEST_URL' research/codex-agent-automation/automation-prompt.md
grep -q 'pavbot_commit_and_push_outputs.sh --isolated research/codex-agent-automation' research/codex-agent-automation/automation-prompt.md
grep -q '\$daily-research-agent' research/tech-news/automation-research-prompt.md
grep -q 'generate_pavbot_manifest.py' research/tech-news/automation-research-prompt.md
grep -q 'PAVBOT_MANIFEST_URL' research/tech-news/automation-research-prompt.md
grep -q 'pavbot_commit_and_push_outputs.sh --isolated --force-manifest research/tech-news' research/tech-news/automation-research-prompt.md
grep -q 'render_research_pdf.py' research/tech-news/automation-research-prompt.md
grep -q 'render_research_pdf.py' .agents/skills/daily-research-agent/SKILL.md
test -s research/tech-news/pdfs/2026-06-18-tech-news.pdf
grep -q '\$daily-tech-podcast-agent' research/tech-news/automation-podcast-prompt.md
grep -q 'generate_pavbot_manifest.py' research/tech-news/automation-podcast-prompt.md
grep -q 'PAVBOT_MANIFEST_URL' research/tech-news/automation-podcast-prompt.md
grep -q 'pavbot_commit_and_push_outputs.sh --isolated research/tech-news' research/tech-news/automation-podcast-prompt.md
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
grep -q 'pavbot_commit_and_push_outputs.sh --isolated --force-manifest research/polska-swiat' research/polska-swiat/automation-research-prompt.md
grep -q '\$daily-news-podcast-agent' research/polska-swiat/automation-podcast-prompt.md
grep -q 'generate_pavbot_manifest.py' research/polska-swiat/automation-podcast-prompt.md
grep -q 'PAVBOT_MANIFEST_URL' research/polska-swiat/automation-podcast-prompt.md
grep -q 'pavbot_commit_and_push_outputs.sh --isolated research/polska-swiat' research/polska-swiat/automation-podcast-prompt.md
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
grep -q 'render_jobs_data.py' docs/how-to-use.md
grep -q 'validate_jobs_data.py' docs/how-to-use.md
grep -q 'data/YYYY-MM-DD-HHMM-jobs.json' docs/how-to-use.md
grep -q 'pavbot_commit_and_push_outputs.sh --isolated research/llm-ai-jobs-wroclaw' docs/how-to-use.md
grep -q 'git fetch origin' docs/how-to-use.md
grep -q 'origin/main:public/pavbot-manifest.json' docs/how-to-use.md
grep -q '\$daily-research-agent' research/llm-ai-jobs-wroclaw/automation-research-prompt.md
grep -q 'generate_pavbot_manifest.py' research/llm-ai-jobs-wroclaw/automation-research-prompt.md
grep -q 'PAVBOT_MANIFEST_URL' research/llm-ai-jobs-wroclaw/automation-research-prompt.md
grep -q 'validate_jobs_data.py' research/llm-ai-jobs-wroclaw/automation-research-prompt.md
grep -q 'render_jobs_data.py' research/llm-ai-jobs-wroclaw/automation-research-prompt.md
grep -q 'data/YYYY-MM-DD-HHMM-jobs.json' research/llm-ai-jobs-wroclaw/automation-research-prompt.md
grep -q 'pavbot_commit_and_push_outputs.sh --isolated research/llm-ai-jobs-wroclaw' research/llm-ai-jobs-wroclaw/automation-research-prompt.md
grep -q 'post-publish verification' research/llm-ai-jobs-wroclaw/automation-research-prompt.md
grep -q 'git fetch origin' research/llm-ai-jobs-wroclaw/automation-research-prompt.md
grep -q 'origin/main:public/pavbot-manifest.json' research/llm-ai-jobs-wroclaw/automation-research-prompt.md
grep -q 'RUN_PATH=' research/llm-ai-jobs-wroclaw/automation-research-prompt.md
grep -q 'DATA_PATH=' research/llm-ai-jobs-wroclaw/automation-research-prompt.md
grep -q 'PDF_PATH=' research/llm-ai-jobs-wroclaw/automation-research-prompt.md
grep -q 'git show "origin/main:$DATA_PATH" >/dev/null' research/llm-ai-jobs-wroclaw/automation-research-prompt.md
grep -q 'Markdown -> jobsData JSON' docs/automation-operations.md
grep -q 'git fetch origin' docs/automation-operations.md
grep -q 'origin/main:public/pavbot-manifest.json' docs/automation-operations.md
grep -q 'pavbot-tech-research-19-33' docs/how-to-use.md
grep -q 'pavbot-tech-research-19-33' docs/automation-operations.md
grep -q 'research/tech-news/data/YYYY-MM-DD-HHMM-research.json' docs/how-to-use.md
grep -q 'research/tech-news/pdfs/YYYY-MM-DD-HHMM-tech-news.pdf' docs/how-to-use.md
grep -q 'pavbot-polska-wiat-research-19-33' docs/how-to-use.md
grep -q 'pavbot-polska-wiat-research-19-33' docs/automation-operations.md
grep -q 'research/polska-swiat/data/YYYY-MM-DD-HHMM-research.json' docs/how-to-use.md
grep -q 'research/polska-swiat/pdfs/YYYY-MM-DD-HHMM-polska-swiat.pdf' docs/how-to-use.md
grep -q 'pavbot-aktualne-wydarzenia-mobile-10-15' docs/how-to-use.md
grep -q 'pavbot-aktualne-wydarzenia-mobile-10-15' docs/automation-operations.md
grep -q 'pavbot-aktualne-wydarzenia-mobile-19-33' docs/how-to-use.md
grep -q 'pavbot-aktualne-wydarzenia-mobile-19-33' docs/automation-operations.md
grep -q '\$daily-research-agent' research/aktualne-wydarzenia-mobile/automation-prompt.md
grep -q 'PAVBOT_MANIFEST_URL' research/aktualne-wydarzenia-mobile/automation-prompt.md
grep -q 'pavbot_commit_and_push_outputs.sh --isolated research/aktualne-wydarzenia-mobile' research/aktualne-wydarzenia-mobile/automation-prompt.md
grep -F -q 'RUN_STAMP=$(TZ=Europe/Warsaw date +%Y-%m-%d-%H%M)' research/aktualne-wydarzenia-mobile/automation-prompt.md
grep -F -q 'RUN_DATE=${RUN_STAMP:0:10}' research/aktualne-wydarzenia-mobile/automation-prompt.md
grep -q 'runs/YYYY-MM-DD-HHMM.md' research/aktualne-wydarzenia-mobile/automation-prompt.md
grep -q 'pdfs/YYYY-MM-DD-HHMM-mobile-brief.pdf' research/aktualne-wydarzenia-mobile/automation-prompt.md
grep -q 'pdfs/YYYY-MM-DD-HHMM-newspaper.pdf' research/aktualne-wydarzenia-mobile/automation-prompt.md
grep -q 'podcasts/YYYY-MM-DD-HHMM/' research/aktualne-wydarzenia-mobile/automation-prompt.md
grep -q 'render_mobile_brief_pdf.py' research/aktualne-wydarzenia-mobile/automation-prompt.md
grep -q 'render_mobile_newspaper_pdf.py' research/aktualne-wydarzenia-mobile/automation-prompt.md
grep -q 'Ogólne' research/aktualne-wydarzenia-mobile/automation-prompt.md
grep -q 'Sprawy zagraniczne' research/aktualne-wydarzenia-mobile/automation-prompt.md
grep -q 'Wprowadzenie' research/aktualne-wydarzenia-mobile/automation-prompt.md
grep -q 'minimum dwa artykuły' research/aktualne-wydarzenia-mobile/automation-prompt.md
grep -q 'render_mobile_news_data.py' research/aktualne-wydarzenia-mobile/automation-prompt.md
grep -q 'validate_mobile_news_data.py' research/aktualne-wydarzenia-mobile/automation-prompt.md
grep -q 'render_two_tts_variants.sh' research/aktualne-wydarzenia-mobile/automation-prompt.md
grep -q 'female-piper' research/aktualne-wydarzenia-mobile/tools/render_two_tts_variants.sh
grep -q 'male-xtts' research/aktualne-wydarzenia-mobile/tools/render_two_tts_variants.sh
grep -q 'podcastAudioVariant' scripts/generate_pavbot_manifest.py
grep -q 'jobsData' scripts/generate_pavbot_manifest.py
grep -q 'case jobsData' ios/PavbotViewer/Sources/Models/PavbotManifest.swift
grep -q 'case pulseNewsData' ios/PavbotViewer/Sources/Models/PavbotManifest.swift
grep -q 'PulseNewsDigest' ios/PavbotViewer/Sources/Models/PulseNewsDigest.swift
grep -q 'TodayLiveTopicPair' ios/PavbotViewer/Sources/Models/TodayLiveTopics.swift
grep -q 'PulseNewsClient' ios/PavbotViewer/Sources/Services/PulseNewsService.swift
grep -q 'pulseNewsData' ios/PavbotViewer/Sources/Services/TodayLiveTopicsService.swift
grep -q 'TodayLiveTopicsPairPage' ios/PavbotViewer/Sources/Views/TodayLiveTopicsView.swift
grep -q 'pavbot-puls-dnia-news-3h' docs/how-to-use.md
grep -q 'pavbot-puls-dnia-news-3h' docs/automation-operations.md
grep -q '\$daily-research-agent' research/puls-dnia-news/automation-prompt.md
grep -q 'validate_pulse_news_data.py' research/puls-dnia-news/automation-prompt.md
grep -q 'data/YYYY-MM-DD-HHMM-pulse-news.json' research/puls-dnia-news/automation-prompt.md
grep -q 'pavbot_commit_and_push_outputs.sh --isolated research/puls-dnia-news' research/puls-dnia-news/automation-prompt.md
grep -q 'pulseNewsData' scripts/generate_pavbot_manifest.py

latest_pulse_news_data="$(
  find research/puls-dnia-news/data -type f -name '*-pulse-news.json' 2>/dev/null \
    | LC_ALL=C sort \
    | tail -n 1
)"
if [[ -n "$latest_pulse_news_data" ]]; then
  python3 - public/pavbot-manifest.json "$latest_pulse_news_data" <<'PY'
import json
import sys
from pathlib import Path

manifest_path = Path(sys.argv[1])
expected_path = sys.argv[2]
manifest = json.loads(manifest_path.read_text(encoding="utf-8"))

for artifact in manifest.get("artifacts", []):
    if (
        artifact.get("path") == expected_path
        and artifact.get("topic") == "puls-dnia-news"
        and artifact.get("type") == "pulseNewsData"
    ):
        raise SystemExit(0)

print(
    f"manifest missing latest pulseNewsData artifact: {expected_path}",
    file=sys.stderr,
)
raise SystemExit(1)
PY
fi

for topic in llm-ai-jobs-wroclaw tech-news polska-swiat; do
  for run_file in "research/$topic"/runs/*.md; do
    [[ -f "$run_file" ]] || continue
    run_stem="$(basename "$run_file" .md)"
    pdf_file="research/$topic/pdfs/$run_stem-$topic.pdf"
    if [[ ! -s "$pdf_file" ]]; then
      printf 'missing required research PDF: %s -> %s\n' "$run_file" "$pdf_file" >&2
      exit 1
    fi
  done
done

for topic in tech-news polska-swiat; do
  for podcast_dir in "research/$topic"/podcasts/*; do
    [[ -d "$podcast_dir" ]] || continue
    if [[ -f "$podcast_dir/podcast.mp3" || -f "$podcast_dir/script.md" || -f "$podcast_dir/render.json" || -f "$podcast_dir/draft.md" || -f "$podcast_dir/sources.md" ]]; then
      if [[ ! -s "$podcast_dir/brief.pdf" ]]; then
        printf 'missing required podcast brief PDF: %s/brief.pdf\n' "$podcast_dir" >&2
        exit 1
      fi
    fi
  done
done

printf 'research workspace verified: %d required files present\n' "${#required_files[@]}"
