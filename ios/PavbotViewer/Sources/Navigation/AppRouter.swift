import Foundation
import Observation

enum AppTab: Hashable {
    case automations
    case artifacts
    case jobs
    case pulseDay
    case research
    case today
    case diagnostics
    case settings
}

extension AppTab {
    var displayTitle: String {
        switch self {
        case .automations:
            "Automatyzacje"
        case .artifacts:
            "Pliki"
        case .jobs:
            "Praca"
        case .pulseDay:
            "Puls Dnia"
        case .research:
            "Przegląd"
        case .today:
            "Dzisiaj"
        case .diagnostics:
            "Diagnostyka"
        case .settings:
            "Ustawienia"
        }
    }

    var systemImage: String {
        switch self {
        case .automations:
            "bolt.circle"
        case .artifacts:
            "folder"
        case .jobs:
            "briefcase"
        case .pulseDay:
            "globe.europe.africa.fill"
        case .research:
            "newspaper"
        case .today:
            "sun.max"
        case .diagnostics:
            "waveform.path.ecg"
        case .settings:
            "gearshape"
        }
    }
}

enum TodaySectionTarget: Hashable {
    case redditRadar
}

struct CloudKitBriefingNotificationRoute: Equatable, Sendable {
    let topic: String
    let stamp: String?

    init?(userInfo: [AnyHashable: Any]) {
        let briefingId = (userInfo["briefingId"] as? String ?? userInfo["briefingID"] as? String)?.nilIfBlank
        let category = (userInfo["category"] as? String ?? userInfo["briefingCategory"] as? String)?.nilIfBlank
        let parts = briefingId?.split(separator: ":", maxSplits: 1).map(String.init) ?? []
        let topic = category ?? parts.first?.nilIfBlank
        guard let topic else { return nil }
        self.topic = topic
        stamp = parts.count > 1 ? parts[1].nilIfBlank : nil
    }
}

@MainActor
@Observable
final class AppRouter {
    var selectedTab: AppTab = .today
    var artifactPath: [PavbotArtifact] = []
    var pendingArtifactID: String?
    var artifactRoute: ArtifactNotificationRoute?
    var selectedArtifactAutomationID: String?
    var selectedArtifactDay: String?
    var selectedWeatherDate: String?
    var selectedTodaySectionTarget: TodaySectionTarget?
    var selectedResearchTopic: ReportTopicKind = .techNews
    var selectedReportDay: String?
    var selectedReportArtifactIDs: [String] = []
    var jobsPath: [PavbotArtifact] = []
    var researchPath: [PavbotArtifact] = []
    var pendingAudioArticleRoute: PavbotAudioDestination?
    private(set) var reportRouteRevision = 0

    func openAudioDestination(_ destination: PavbotAudioDestination) {
        switch destination {
        case .mobileNewsArticle:
            selectedResearchTopic = .aktualne
        case .researchArticle(let topic, _):
            selectedResearchTopic = topic
        }
        selectedTab = .research
        pendingAudioArticleRoute = destination
        artifactPath = []
        selectedTodaySectionTarget = nil
        jobsPath = []
        researchPath = []
    }

    func clearPendingAudioArticleRoute(_ destination: PavbotAudioDestination) {
        guard pendingAudioArticleRoute == destination else { return }
        pendingAudioArticleRoute = nil
    }

    func openArtifact(_ artifact: PavbotArtifact) {
        if let reportTopic = ReportTopicKind(topic: artifact.topic) {
            selectedTab = reportTopic == .jobs ? .jobs : .research
            selectedResearchTopic = reportTopic == .jobs ? selectedResearchTopic : reportTopic
            selectedReportDay = artifact.date
            selectedReportArtifactIDs = []
            artifactPath = []
            jobsPath = reportTopic == .jobs ? [artifact] : []
            researchPath = reportTopic == .jobs ? [] : [artifact]
        } else {
            selectedTab = .artifacts
            artifactPath = [artifact]
            selectedReportArtifactIDs = []
            jobsPath = []
            researchPath = []
        }
        pendingArtifactID = nil
        artifactRoute = nil
        selectedArtifactAutomationID = nil
        selectedArtifactDay = nil
        selectedWeatherDate = nil
        selectedTodaySectionTarget = nil
    }

    func openArtifactRoute(_ route: ArtifactNotificationRoute) {
        selectedTab = .artifacts
        artifactPath = []
        pendingArtifactID = nil
        artifactRoute = route
        selectedArtifactAutomationID = nil
        selectedArtifactDay = route.date
        selectedWeatherDate = nil
        selectedTodaySectionTarget = nil
        selectedReportDay = nil
        selectedReportArtifactIDs = []
        jobsPath = []
        researchPath = []
    }

    func clearArtifactRoute() {
        artifactRoute = nil
        selectedArtifactAutomationID = nil
        selectedArtifactDay = nil
        selectedWeatherDate = nil
        selectedTodaySectionTarget = nil
        selectedReportDay = nil
        selectedReportArtifactIDs = []
        jobsPath = []
        researchPath = []
    }

    func selectArtifactAutomation(id: String?, day: String?, switchToArtifactsTab: Bool = true) {
        if switchToArtifactsTab {
            selectedTab = .artifacts
        }
        artifactPath = []
        pendingArtifactID = nil
        artifactRoute = nil
        selectedArtifactAutomationID = id
        selectedArtifactDay = day
        selectedWeatherDate = nil
        selectedTodaySectionTarget = nil
        selectedReportDay = nil
        selectedReportArtifactIDs = []
        jobsPath = []
        researchPath = []
    }

    func openArtifactsForAutomation(id: String, latestDay: String?, switchToArtifactsTab: Bool = true) {
        selectArtifactAutomation(id: id, day: latestDay, switchToArtifactsTab: switchToArtifactsTab)
    }

    func openReportsForTopic(_ topic: String, latestDay: String?) -> Bool {
        if topic == "puls-dnia-news" {
            openPulseDay(date: latestDay, artifactIDs: [])
            advanceReportRouteRevision()
            return true
        }
        if topic == "reddit-radar" {
            openTodaySection(.redditRadar)
            return true
        }

        guard let reportTopic = ReportTopicKind(topic: topic) else {
            return false
        }
        selectedTab = reportTopic == .jobs ? .jobs : .research
        if reportTopic != .jobs {
            selectedResearchTopic = reportTopic
        }
        selectedReportDay = latestDay
        selectedReportArtifactIDs = []
        artifactPath = []
        pendingArtifactID = nil
        artifactRoute = nil
        selectedArtifactAutomationID = nil
        selectedArtifactDay = nil
        selectedWeatherDate = nil
        selectedTodaySectionTarget = nil
        jobsPath = []
        researchPath = []
        advanceReportRouteRevision()
        return true
    }

    func openDailyWeather(date: String?) {
        selectedTab = .today
        artifactPath = []
        pendingArtifactID = nil
        artifactRoute = nil
        selectedArtifactAutomationID = nil
        selectedArtifactDay = nil
        selectedWeatherDate = date
        selectedTodaySectionTarget = nil
        selectedReportDay = nil
        selectedReportArtifactIDs = []
        jobsPath = []
        researchPath = []
    }

    func openPulseDay(date: String?, artifactIDs: [String]) {
        selectedTab = .pulseDay
        artifactPath = []
        pendingArtifactID = nil
        artifactRoute = nil
        selectedArtifactAutomationID = nil
        selectedArtifactDay = nil
        selectedWeatherDate = nil
        selectedTodaySectionTarget = nil
        selectedReportDay = date
        selectedReportArtifactIDs = artifactIDs
        jobsPath = []
        researchPath = []
    }

    func openTodaySection(_ target: TodaySectionTarget) {
        selectedTab = .today
        artifactPath = []
        pendingArtifactID = nil
        artifactRoute = nil
        selectedArtifactAutomationID = nil
        selectedArtifactDay = nil
        selectedWeatherDate = nil
        selectedTodaySectionTarget = target
        selectedReportDay = nil
        selectedReportArtifactIDs = []
        jobsPath = []
        researchPath = []
    }

    func clearTodaySectionTarget(_ target: TodaySectionTarget) {
        guard selectedTodaySectionTarget == target else { return }
        selectedTodaySectionTarget = nil
    }

    func openReportRoute(_ route: ArtifactNotificationRoute) -> Bool {
        if route.topic == "puls-dnia-news" {
            openPulseDay(date: route.date, artifactIDs: route.artifactIDs)
            advanceReportRouteRevision()
            return true
        }
        if route.topic == "reddit-radar" {
            openTodaySection(.redditRadar)
            return true
        }

        guard let topic = route.topic, let reportTopic = ReportTopicKind(topic: topic) else {
            return false
        }

        selectedTab = reportTopic == .jobs ? .jobs : .research
        if reportTopic != .jobs {
            selectedResearchTopic = reportTopic
        }
        selectedReportDay = route.date
        selectedReportArtifactIDs = route.artifactIDs
        artifactPath = []
        pendingArtifactID = nil
        artifactRoute = nil
        selectedArtifactAutomationID = nil
        selectedArtifactDay = nil
        selectedWeatherDate = nil
        selectedTodaySectionTarget = nil
        jobsPath = []
        researchPath = []
        advanceReportRouteRevision()
        return true
    }

    func handleNotification(userInfo: [AnyHashable: Any]) {
        if userInfo["notificationKind"] as? String == "dailyWeather" {
            openDailyWeather(date: userInfo["weatherDate"] as? String)
            return
        }
        if let briefingRoute = CloudKitBriefingNotificationRoute(userInfo: userInfo) {
            if openReportsForTopic(briefingRoute.topic, latestDay: briefingRoute.stamp) {
                return
            }
        }
        if let route = ArtifactNotificationRoute(userInfo: userInfo) {
            if openReportRoute(route) {
                return
            }
            openArtifactRoute(route)
            return
        }
        if let artifactID = userInfo["artifactID"] as? String {
            artifactPath = []
            pendingArtifactID = artifactID
            artifactRoute = nil
            selectedArtifactAutomationID = nil
            selectedArtifactDay = nil
            selectedWeatherDate = nil
            selectedTodaySectionTarget = nil
            selectedReportDay = nil
            selectedReportArtifactIDs = []
            jobsPath = []
            researchPath = []
            return
        }
        if userInfo["automationID"] is String {
            selectedTab = .settings
            artifactPath = []
            pendingArtifactID = nil
            artifactRoute = nil
            selectedArtifactAutomationID = nil
            selectedArtifactDay = nil
            selectedWeatherDate = nil
            selectedTodaySectionTarget = nil
            selectedReportDay = nil
            selectedReportArtifactIDs = []
            jobsPath = []
            researchPath = []
        }
    }

    func handleOpenURL(_ url: URL) {
        guard url.scheme == "pavbot", url.host == "artifact" else { return }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        guard let artifactID = components?.queryItems?.first(where: { $0.name == "id" })?.value, !artifactID.isEmpty else {
            return
        }
        selectedTab = .artifacts
        artifactPath = []
        pendingArtifactID = artifactID
        artifactRoute = nil
        selectedArtifactAutomationID = nil
        selectedArtifactDay = nil
        selectedWeatherDate = nil
        selectedTodaySectionTarget = nil
        selectedReportDay = nil
        selectedReportArtifactIDs = []
        jobsPath = []
        researchPath = []
    }

    func resolvePendingArtifact(in manifest: PavbotManifest?) {
        guard
            let pendingArtifactID,
            let artifact = manifest?.artifacts.first(where: { $0.id == pendingArtifactID })
        else {
            return
        }
        openArtifact(artifact)
    }

    func resolveArtifactRouteSelection(in manifest: PavbotManifest?) {
        guard let route = artifactRoute, let manifest else { return }
        selectedArtifactDay = route.date

        if let selectedArtifactAutomationID,
           manifest.artifactCollection(for: selectedArtifactAutomationID) != nil {
            return
        }

        selectedArtifactAutomationID = manifest.artifactCollection(for: route)?.id
    }

    private func advanceReportRouteRevision() {
        reportRouteRevision += 1
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
