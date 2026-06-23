import Foundation
import UIKit
import UserNotifications

@MainActor
protocol ArtifactNotifying {
    func notify(artifacts: [PavbotArtifact], automations: [PavbotAutomation], manifestURL: URL) async
}

struct ArtifactNotificationService: ArtifactNotifying {
    func notify(artifacts: [PavbotArtifact], automations: [PavbotAutomation], manifestURL: URL) async {
        guard !artifacts.isEmpty || !automations.isEmpty else { return }

        let center = UNUserNotificationCenter.current()
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            guard granted else { return }
        } catch {
            return
        }

        if !artifacts.isEmpty {
            let route = ArtifactNotificationRoute(artifacts: artifacts)
            let content = UNMutableNotificationContent()
            content.title = "Pavbot"
            content.body = Self.summaryBody(for: artifacts, route: route)
            content.sound = .default
            var userInfo = route.userInfo
            userInfo["manifestURL"] = manifestURL.absoluteString
            content.userInfo = userInfo

            let request = UNNotificationRequest(
                identifier: "pavbot.summary.\((route.artifactIDs.first ?? UUID().uuidString).notificationIdentifierComponent)",
                content: content,
                trigger: nil
            )
            try? await center.add(request)
        }

        if artifacts.isEmpty, !automations.isEmpty {
            let content = UNMutableNotificationContent()
            content.title = "Pavbot"
            content.body = automations.count == 1
                ? "New automation · \(automations[0].name)"
                : "\(automations.count) new automations"
            content.sound = .default
            content.userInfo = [
                "automationID": automations[0].id,
                "automationIDs": automations.map(\.id),
                "manifestURL": manifestURL.absoluteString
            ]

            let request = UNNotificationRequest(
                identifier: "pavbot.automation.\(automations[0].id.notificationIdentifierComponent)",
                content: content,
                trigger: nil
            )
            try? await center.add(request)
        }
    }

    private static func summaryBody(for artifacts: [PavbotArtifact], route: ArtifactNotificationRoute) -> String {
        let fileLabel = artifacts.count == 1 ? "file" : "files"
        return "\(route.displayTitle) · \(artifacts.count) new \(fileLabel)"
    }
}

enum NotificationServerSettings {
    static let urlDefaultsKey = "pavbot.notificationServerURL"

    static var serverURLString: String {
        get {
            UserDefaults.standard.string(forKey: urlDefaultsKey) ?? ""
        }
        set {
            UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: urlDefaultsKey)
        }
    }

    static var serverURL: URL? {
        let trimmed = serverURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(string: trimmed)
    }

    static func validationMessage(for value: String, required: Bool) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return required ? "Enter a notification server URL before enabling live alerts." : nil
        }
        guard
            let url = URL(string: trimmed),
            url.scheme == "https",
            url.host?.isEmpty == false
        else {
            return "Use an HTTPS notification server URL."
        }
        return nil
    }
}

enum LiveNotificationOnboarding {
    static let promptSeenDefaultsKey = "pavbot.liveNotificationsPromptSeen"

    static func shouldPrompt(defaults: UserDefaults = .standard) -> Bool {
        !defaults.bool(forKey: promptSeenDefaultsKey)
    }

    static func markPromptSeen(defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: promptSeenDefaultsKey)
    }

    static func needsSettingsBeforeSystemPrompt(serverURLString: String) -> Bool {
        NotificationServerSettings.validationMessage(for: serverURLString, required: true) != nil
    }
}

@MainActor
enum RemoteNotificationPermission {
    static func requestAndRegister() async -> Bool {
        let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        if granted {
            UIApplication.shared.registerForRemoteNotifications()
        }
        return granted
    }
}

enum RemoteNotificationDiagnostics {
    static let deviceTokenDefaultsKey = "pavbot.lastRemoteNotificationDeviceToken"
    static let registrationErrorDefaultsKey = "pavbot.lastRemoteNotificationRegistrationError"

    static func saveDeviceToken(_ deviceToken: Data, defaults: UserDefaults = .standard) {
        defaults.set(deviceToken.hexString, forKey: deviceTokenDefaultsKey)
    }

    static func deviceToken(defaults: UserDefaults = .standard) -> String {
        defaults.string(forKey: deviceTokenDefaultsKey) ?? ""
    }

    static func deviceTokenPreview(defaults: UserDefaults = .standard) -> String {
        deviceTokenPreview(for: deviceToken(defaults: defaults))
    }

    static func deviceTokenPreview(for token: String) -> String {
        guard !token.isEmpty else { return "Not registered" }
        guard token.count > 8 else { return token }
        return "\(token.prefix(4))...\(token.suffix(4))"
    }

    static func saveRegistrationError(_ message: String, defaults: UserDefaults = .standard) {
        defaults.set(message, forKey: registrationErrorDefaultsKey)
    }

    static func registrationError(defaults: UserDefaults = .standard) -> String {
        defaults.string(forKey: registrationErrorDefaultsKey) ?? ""
    }

    static func clearRegistrationError(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: registrationErrorDefaultsKey)
    }
}

struct RemoteNotificationRegistrar {
    struct RegistrationPayload: Encodable {
        let deviceToken: String
        let platform: String
        let bundleId: String
        let manifestURL: String
        let appVersion: String
        let buildNumber: String
    }

    var session: URLSession = .shared

    func register(deviceToken: Data) async {
        guard let endpoint = NotificationServerSettings.serverURL?.appendingPathComponent("v1/devices") else {
            return
        }

        let bundle = Bundle.main
        let payload = RegistrationPayload(
            deviceToken: deviceToken.hexString,
            platform: "ios",
            bundleId: bundle.bundleIdentifier ?? "com.paweltanski.pavbotviewer",
            manifestURL: UserDefaults.standard.string(forKey: ManifestDefaults.urlDefaultsKey) ?? ManifestDefaults.defaultManifestURL,
            appVersion: bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "",
            buildNumber: bundle.infoDictionary?["CFBundleVersion"] as? String ?? ""
        )

        do {
            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(payload)
            _ = try await session.data(for: request)
        } catch {
            return
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
        let userInfo = response.notification.request.content.userInfo
        let route = ArtifactNotificationRoute(userInfo: userInfo)
        let artifactID = userInfo["artifactID"] as? String
        let automationID = userInfo["automationID"] as? String
        await MainActor.run {
            if let route {
                router?.openArtifactRoute(route)
            } else if let artifactID {
                router?.handleNotification(userInfo: ["artifactID": artifactID])
            } else if let automationID {
                router?.handleNotification(userInfo: ["automationID": automationID])
            }
        }
    }
}

final class PavbotRemoteNotificationAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        RemoteNotificationDiagnostics.saveDeviceToken(deviceToken)
        RemoteNotificationDiagnostics.clearRegistrationError()
        Task {
            await RemoteNotificationRegistrar().register(deviceToken: deviceToken)
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        RemoteNotificationDiagnostics.saveRegistrationError(error.localizedDescription)
    }

}

private extension String {
    var notificationIdentifierComponent: String {
        components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: ".")
    }
}

private extension Data {
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
