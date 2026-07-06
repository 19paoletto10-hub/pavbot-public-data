import Foundation
import CloudKit
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
                ? "Nowa automatyzacja · \(automations[0].name)"
                : "\(automations.count) nowe automatyzacje"
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
        let fileLabel = artifacts.count == 1 ? "nowy plik" : "nowe pliki"
        return "\(route.displayTitle) · \(artifacts.count) \(fileLabel)"
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

}

enum RemoteNotificationRegistrationPolicy {
    static func shouldRegister(
        liveNotificationsEnabled: Bool,
        authorizationStatus: UNAuthorizationStatus
    ) -> Bool {
        guard liveNotificationsEnabled else { return false }
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
        guard CloudKitRuntimeSupport.shouldUseCloudKitRuntime() else {
            LiveNotificationSettings.setEnabled(false)
            RemoteNotificationDiagnostics.saveRegistrationError(CloudKitRuntimeSupport.disabledInUnitTestsMessage)
            return false
        }

        let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        if granted {
            RemoteNotificationDiagnostics.saveRegistrationAttempt()
            do {
                try await CloudKitService.shared.createOrUpdateSubscriptions()
                LiveNotificationSettings.setEnabled(true)
                RemoteNotificationDiagnostics.saveRegistrationSuccess()
                UIApplication.shared.registerForRemoteNotifications()
            } catch {
                LiveNotificationSettings.setEnabled(false)
                RemoteNotificationDiagnostics.saveRegistrationError("CloudKit subscription failed: \(error.localizedDescription)")
                return false
            }
        } else {
            LiveNotificationSettings.setEnabled(false)
            RemoteNotificationDiagnostics.saveRegistrationError("Zgoda na powiadomienia nie została udzielona.")
        }
        return granted
    }

    static func refreshRegistrationIfNeeded() async {
        guard CloudKitRuntimeSupport.shouldUseCloudKitRuntime() else {
            RemoteNotificationDiagnostics.saveRegistrationError(CloudKitRuntimeSupport.disabledInUnitTestsMessage)
            return
        }

        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard RemoteNotificationRegistrationPolicy.shouldRegister(
            liveNotificationsEnabled: LiveNotificationSettings.isEnabled(),
            authorizationStatus: settings.authorizationStatus
        ) else {
            return
        }

        RemoteNotificationDiagnostics.saveRegistrationAttempt()
        do {
            try await CloudKitService.shared.createOrUpdateSubscriptions()
            RemoteNotificationDiagnostics.saveRegistrationSuccess()
            UIApplication.shared.registerForRemoteNotifications()
        } catch {
            RemoteNotificationDiagnostics.saveRegistrationError("CloudKit subscription failed: \(error.localizedDescription)")
        }
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

    static func hasRegisteredDeviceToken(defaults: UserDefaults = .standard) -> Bool {
        !deviceToken(defaults: defaults).isEmpty
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

    static func saveRegistrationSuccess(defaults: UserDefaults = .standard) {
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
    case cloudKitBriefing(CloudKitBriefingNotificationRoute)
    case artifactRoute(ArtifactNotificationRoute)
    case artifactID(String)
    case automationID(String)
    case none

    init(userInfo: [AnyHashable: Any]) {
        if userInfo["notificationKind"] as? String == "dailyWeather" {
            self = .dailyWeather(date: userInfo["weatherDate"] as? String)
            return
        }
        if let queryNotification = CKNotification(fromRemoteNotificationDictionary: userInfo) as? CKQueryNotification,
           queryNotification.subscriptionID == CloudKitService.briefingsReadySubscriptionID {
            var routeUserInfo: [AnyHashable: Any] = [:]
            if let recordFields = queryNotification.recordFields {
                for key in ["briefingId", "title", "summary", "manifestUrl", "category"] {
                    if let value = recordFields[key] {
                        routeUserInfo[key] = value
                    }
                }
                if let createdAt = recordFields["createdAt"] as? Date {
                    routeUserInfo["createdAt"] = ISO8601DateFormatter().string(from: createdAt)
                } else if let createdAt = recordFields["createdAt"] {
                    routeUserInfo["createdAt"] = createdAt
                }
            }
            if let route = CloudKitBriefingNotificationRoute(userInfo: routeUserInfo) {
                self = .cloudKitBriefing(route)
                return
            }
        }
        if let route = CloudKitBriefingNotificationRoute(userInfo: userInfo) {
            self = .cloudKitBriefing(route)
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
        case .cloudKitBriefing(let route):
            _ = router.openReportsForTopic(route.topic, latestDay: route.stamp)
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
        RemoteNotificationDiagnostics.saveRegistrationSuccess()
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        LiveNotificationSettings.setEnabled(false)
        RemoteNotificationDiagnostics.saveRegistrationError("APNs registration failed: \(error.localizedDescription)")
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        Task { @MainActor in
            let cloudKitNotification = CKNotification(fromRemoteNotificationDictionary: userInfo)
            if cloudKitNotification?.subscriptionID == CloudKitService.briefingsReadySubscriptionID {
                let result = await CloudKitPushRefreshCenter.shared.handleRemoteNotification(userInfo)
                completionHandler(result)
            } else {
                completionHandler(.noData)
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

private extension Data {
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
