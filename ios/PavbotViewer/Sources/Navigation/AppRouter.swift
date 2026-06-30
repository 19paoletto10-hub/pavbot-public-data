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
    var selectedResearchTopic: ReportTopicKind = .techNews
    var selectedReportDay: String?
    var selectedReportArtifactIDs: [String] = []
    var jobsPath: [PavbotArtifact] = []
    var researchPath: [PavbotArtifact] = []

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
    }

    func openArtifactRoute(_ route: ArtifactNotificationRoute) {
        selectedTab = .artifacts
        artifactPath = []
        pendingArtifactID = nil
        artifactRoute = route
        selectedArtifactAutomationID = nil
        selectedArtifactDay = route.date
        selectedWeatherDate = nil
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
        jobsPath = []
        researchPath = []
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
        selectedReportDay = date
        selectedReportArtifactIDs = artifactIDs
        jobsPath = []
        researchPath = []
    }

    func openReportRoute(_ route: ArtifactNotificationRoute) -> Bool {
        if route.topic == "puls-dnia-news" {
            openPulseDay(date: route.date, artifactIDs: route.artifactIDs)
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
        jobsPath = []
        researchPath = []
        return true
    }

    func handleNotification(userInfo: [AnyHashable: Any]) {
        if userInfo["notificationKind"] as? String == "dailyWeather" {
            openDailyWeather(date: userInfo["weatherDate"] as? String)
            return
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
           manifest.automationArtifactGroup(for: selectedArtifactAutomationID) != nil {
            return
        }

        selectedArtifactAutomationID = manifest.automationArtifactGroup(for: route)?.id
    }
}
