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

enum LiveNotificationSettings {
    static let enabledDefaultsKey = "pavbot.liveNotificationsEnabled"

    static func isEnabled(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: enabledDefaultsKey)
    }

    static func setEnabled(_ enabled: Bool, defaults: UserDefaults = .standard) {
        defaults.set(enabled, forKey: enabledDefaultsKey)
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

enum RemoteNotificationRegistrationPolicy {
    static func shouldRegister(
        liveNotificationsEnabled: Bool,
        serverURLString: String,
        authorizationStatus: UNAuthorizationStatus
    ) -> Bool {
        guard liveNotificationsEnabled else { return false }
        guard NotificationServerSettings.validationMessage(for: serverURLString, required: true) == nil else {
            return false
        }
        switch authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied, .notDetermined:
            return false
        @unknown default:
            return false
        }
    }
}

@MainActor
enum RemoteNotificationPermission {
    static func requestAndRegister() async -> Bool {
        guard NotificationServerSettings.validationMessage(for: NotificationServerSettings.serverURLString, required: true) == nil else {
            LiveNotificationSettings.setEnabled(false)
            RemoteNotificationDiagnostics.saveRegistrationError("Notification server URL is missing or invalid.")
            return false
        }

        let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        if granted {
            LiveNotificationSettings.setEnabled(true)
            RemoteNotificationDiagnostics.saveRegistrationAttempt()
            UIApplication.shared.registerForRemoteNotifications()
        } else {
            LiveNotificationSettings.setEnabled(false)
            RemoteNotificationDiagnostics.saveRegistrationError("Notification permission was not granted.")
        }
        return granted
    }

    static func refreshRegistrationIfNeeded() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard RemoteNotificationRegistrationPolicy.shouldRegister(
            liveNotificationsEnabled: LiveNotificationSettings.isEnabled(),
            serverURLString: NotificationServerSettings.serverURLString,
            authorizationStatus: settings.authorizationStatus
        ) else {
            return
        }

        RemoteNotificationDiagnostics.saveRegistrationAttempt()
        UIApplication.shared.registerForRemoteNotifications()
    }
}

enum RemoteNotificationDiagnostics {
    static let deviceTokenDefaultsKey = "pavbot.lastRemoteNotificationDeviceToken"
    static let registrationErrorDefaultsKey = "pavbot.lastRemoteNotificationRegistrationError"
    static let registrationStatusDefaultsKey = "pavbot.lastRemoteNotificationRegistrationStatus"
    static let lastRegisteredAtDefaultsKey = "pavbot.lastRemoteNotificationRegisteredAt"
    static let apnsEnvironmentDefaultsKey = "pavbot.apnsEnvironment"

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
        guard !token.isEmpty else { return "Nie zarejestrowano" }
        guard token.count > 8 else { return token }
        return "\(token.prefix(4))...\(token.suffix(4))"
    }

    static func saveRegistrationError(_ message: String, defaults: UserDefaults = .standard) {
        defaults.set("Błąd", forKey: registrationStatusDefaultsKey)
        defaults.set(message, forKey: registrationErrorDefaultsKey)
    }

    static func registrationError(defaults: UserDefaults = .standard) -> String {
        defaults.string(forKey: registrationErrorDefaultsKey) ?? ""
    }

    static func clearRegistrationError(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: registrationErrorDefaultsKey)
    }

    static func saveRegistrationAttempt(defaults: UserDefaults = .standard) {
        defaults.set("Rejestrowanie", forKey: registrationStatusDefaultsKey)
    }

    static func saveBackendRegistrationSuccess(defaults: UserDefaults = .standard) {
        defaults.set("Zarejestrowano", forKey: registrationStatusDefaultsKey)
        defaults.set(ISO8601DateFormatter().string(from: Date()), forKey: lastRegisteredAtDefaultsKey)
        clearRegistrationError(defaults: defaults)
    }

    static func registrationStatus(defaults: UserDefaults = .standard) -> String {
        switch defaults.string(forKey: registrationStatusDefaultsKey) {
        case "Registered":
            return "Zarejestrowano"
        case "Registering":
            return "Rejestrowanie"
        case "Failed":
            return "Błąd"
        case let value?:
            return value
        case nil:
            return "Nie zarejestrowano"
        }
    }

    static func lastRegisteredAt(defaults: UserDefaults = .standard) -> String {
        defaults.string(forKey: lastRegisteredAtDefaultsKey) ?? ""
    }

    static func apnsEnvironmentLabel() -> String {
        #if DEBUG
        return "Development"
        #else
        return "Production"
        #endif
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
        let dailyWeatherEnabled: Bool
    }

    var session: URLSession = .shared

    func register(deviceToken: Data) async {
        guard let endpoint = NotificationServerSettings.serverURL?.appendingPathComponent("v1/devices") else {
            RemoteNotificationDiagnostics.saveRegistrationError("Notification server URL is missing.")
            return
        }

        let bundle = Bundle.main
        let payload = RegistrationPayload(
            deviceToken: deviceToken.hexString,
            platform: "ios",
            bundleId: bundle.bundleIdentifier ?? "com.paweltanski.pavbotviewer",
            manifestURL: UserDefaults.standard.string(forKey: ManifestDefaults.urlDefaultsKey) ?? ManifestDefaults.defaultManifestURL,
            appVersion: bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "",
            buildNumber: bundle.infoDictionary?["CFBundleVersion"] as? String ?? "",
            dailyWeatherEnabled: DailyWeatherNotificationSettings.isEnabled()
        )

        do {
            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(payload)
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                RemoteNotificationDiagnostics.saveRegistrationError("Serwer powiadomień zwrócił nieprawidłową odpowiedź.")
                return
            }
            guard (200..<300).contains(httpResponse.statusCode) else {
                let responseBody = String(data: data, encoding: .utf8) ?? ""
                let suffix = responseBody.isEmpty ? "" : " \(String(responseBody.prefix(240)))"
                RemoteNotificationDiagnostics.saveRegistrationError("Serwer powiadomień zwrócił HTTP \(httpResponse.statusCode).\(suffix)")
                return
            }
            RemoteNotificationDiagnostics.saveBackendRegistrationSuccess()
        } catch {
            RemoteNotificationDiagnostics.saveRegistrationError(PavbotUserFacingError.network(error, context: .notifier).message)
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
        let command = NotificationRoutingCommand(userInfo: response.notification.request.content.userInfo)
        await MainActor.run {
            guard let router else { return }
            command.apply(to: router)
        }
    }
}

private enum NotificationRoutingCommand: Sendable {
    case dailyWeather(date: String?)
    case artifactRoute(ArtifactNotificationRoute)
    case artifactID(String)
    case automationID(String)
    case none

    init(userInfo: [AnyHashable: Any]) {
        if userInfo["notificationKind"] as? String == "dailyWeather" {
            self = .dailyWeather(date: userInfo["weatherDate"] as? String)
            return
        }
        if let route = ArtifactNotificationRoute(userInfo: userInfo) {
            self = .artifactRoute(route)
            return
        }
        if let artifactID = userInfo["artifactID"] as? String {
            self = .artifactID(artifactID)
            return
        }
        if let automationID = userInfo["automationID"] as? String {
            self = .automationID(automationID)
            return
        }
        self = .none
    }

    @MainActor
    func apply(to router: AppRouter) {
        switch self {
        case .dailyWeather(let date):
            router.openDailyWeather(date: date)
        case .artifactRoute(let route):
            if !router.openReportRoute(route) {
                router.openArtifactRoute(route)
            }
        case .artifactID(let artifactID):
            router.handleNotification(userInfo: ["artifactID": artifactID])
        case .automationID(let automationID):
            router.handleNotification(userInfo: ["automationID": automationID])
        case .none:
            break
        }
    }
}

final class PavbotRemoteNotificationAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        RemoteNotificationDiagnostics.saveDeviceToken(deviceToken)
        RemoteNotificationDiagnostics.saveRegistrationAttempt()
        Task {
            await RemoteNotificationRegistrar().register(deviceToken: deviceToken)
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        RemoteNotificationDiagnostics.saveRegistrationError(PavbotUserFacingError.network(error, context: .notifier).message)
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
