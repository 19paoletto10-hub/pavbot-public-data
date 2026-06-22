import Foundation
import UserNotifications

@MainActor
protocol ArtifactNotifying {
    func notify(artifacts: [PavbotArtifact], manifestURL: URL) async
}

struct ArtifactNotificationService: ArtifactNotifying {
    func notify(artifacts: [PavbotArtifact], manifestURL: URL) async {
        guard !artifacts.isEmpty else { return }

        let center = UNUserNotificationCenter.current()
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            guard granted else { return }
        } catch {
            return
        }

        for artifact in artifacts.prefix(8) {
            let content = UNMutableNotificationContent()
            content.title = "New \(artifact.type.label)"
            content.body = "\(artifact.topic) · \(artifact.title)"
            content.sound = .default
            content.userInfo = [
                "artifactID": artifact.id,
                "artifactPath": artifact.path,
                "manifestURL": manifestURL.absoluteString
            ]

            let request = UNNotificationRequest(
                identifier: "pavbot.\(artifact.id.notificationIdentifierComponent)",
                content: content,
                trigger: nil
            )
            try? await center.add(request)
        }
    }
}

final class ArtifactNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    private weak var router: AppRouter?

    @MainActor
    func install(router: AppRouter) {
        self.router = router
        UNUserNotificationCenter.current().delegate = self
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let artifactID = response.notification.request.content.userInfo["artifactID"] as? String
        await MainActor.run {
            if let artifactID {
                router?.handleNotification(userInfo: ["artifactID": artifactID])
            }
        }
    }
}

private extension String {
    var notificationIdentifierComponent: String {
        components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: ".")
    }
}
