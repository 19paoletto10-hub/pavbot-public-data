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

    func openArtifact(_ artifact: PavbotArtifact) {
        selectedTab = .artifacts
        artifactPath = [artifact]
        pendingArtifactID = nil
    }

    func handleNotification(userInfo: [AnyHashable: Any]) {
        pendingArtifactID = userInfo["artifactID"] as? String
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
