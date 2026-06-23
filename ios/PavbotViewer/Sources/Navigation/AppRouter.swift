import Foundation
import Observation

enum AppTab: Hashable {
    case automations
    case artifacts
    case diagnostics
    case settings
}

@MainActor
@Observable
final class AppRouter {
    var selectedTab: AppTab = .automations
    var artifactPath: [PavbotArtifact] = []
    var pendingArtifactID: String?
    var artifactRoute: ArtifactNotificationRoute?

    func openArtifact(_ artifact: PavbotArtifact) {
        selectedTab = .artifacts
        artifactPath = [artifact]
        pendingArtifactID = nil
        artifactRoute = nil
    }

    func openArtifactRoute(_ route: ArtifactNotificationRoute) {
        selectedTab = .artifacts
        artifactPath = []
        pendingArtifactID = nil
        artifactRoute = route
    }

    func clearArtifactRoute() {
        artifactRoute = nil
    }

    func handleNotification(userInfo: [AnyHashable: Any]) {
        if let route = ArtifactNotificationRoute(userInfo: userInfo) {
            openArtifactRoute(route)
            return
        }
        if let artifactID = userInfo["artifactID"] as? String {
            pendingArtifactID = artifactID
            artifactRoute = nil
            return
        }
        if userInfo["automationID"] is String {
            selectedTab = .automations
            artifactPath = []
            pendingArtifactID = nil
            artifactRoute = nil
        }
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
}
