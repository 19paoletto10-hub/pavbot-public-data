import Foundation
import CloudKit
import UIKit
import UserNotifications

@MainActor
protocol ArtifactNotifying {
    func notify(artifacts: [PavbotArtifact], automations: [PavbotAutomation], manifestURL: URL) async
}

@MainActor
protocol LocalNotificationScheduling {
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool
    func add(_ request: UNNotificationRequest) async throws
}

extension UNUserNotificationCenter: LocalNotificationScheduling {}

@MainActor
protocol LocalNotificationDiagnosticsRecording {
    func saveLocalNotificationDeliveryError(_ message: String)
}

struct RemoteNotificationDiagnosticsRecorder: LocalNotificationDiagnosticsRecording {
    func saveLocalNotificationDeliveryError(_ message: String) {
        RemoteNotificationDiagnostics.saveLocalNotificationDeliveryError(message)
    }
}

@MainActor
struct ArtifactNotificationService: ArtifactNotifying {
    private let center: any LocalNotificationScheduling
    private let diagnostics: any LocalNotificationDiagnosticsRecording

    init(
        center: (any LocalNotificationScheduling)? = nil,
        diagnostics: (any LocalNotificationDiagnosticsRecording)? = nil
    ) {
        self.center = center ?? UNUserNotificationCenter.current()
        self.diagnostics = diagnostics ?? RemoteNotificationDiagnosticsRecorder()
    }

    func notify(artifacts: [PavbotArtifact], automations: [PavbotAutomation], manifestURL: URL) async {
        guard !artifacts.isEmpty || !automations.isEmpty else { return }

        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            guard granted else { return }
        } catch {
            diagnostics.saveLocalNotificationDeliveryError("Notification authorization failed: \(error.localizedDescription)")
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
            await schedule(request)
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
            await schedule(request)
        }
    }

    private func schedule(_ request: UNNotificationRequest) async {
        do {
            try await center.add(request)
            diagnostics.saveLocalNotificationDeliveryError("")
        } catch {
            diagnostics.saveLocalNotificationDeliveryError("Local notification scheduling failed: \(error.localizedDescription)")
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
    static func requestAndRegister(mode: CloudKitBriefingNotificationMode = .load()) async -> Bool {
        let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        if granted {
            LiveNotificationSettings.setEnabled(true)
            RemoteNotificationDiagnostics.saveRegistrationAttempt()
            do {
                CloudKitBriefingNotificationMode.save(mode)
                try await CloudKitService.shared.createOrUpdateSubscriptions(mode: mode)
                RemoteNotificationDiagnostics.saveRegistrationSuccess()
                UIApplication.shared.registerForRemoteNotifications()
            } catch {
                RemoteNotificationDiagnostics.saveRegistrationError("CloudKit subscription failed: \(error.localizedDescription)")
                return false
            }
        } else {
            LiveNotificationSettings.setEnabled(false)
            RemoteNotificationDiagnostics.saveRegistrationError("Zgoda na powiadomienia nie została udzielona.")
        }
        return granted
    }

    static func refreshRegistrationIfNeeded(mode: CloudKitBriefingNotificationMode = .load()) async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard RemoteNotificationRegistrationPolicy.shouldRegister(
            liveNotificationsEnabled: LiveNotificationSettings.isEnabled(),
            authorizationStatus: settings.authorizationStatus
        ) else {
            return
        }

        RemoteNotificationDiagnostics.saveRegistrationAttempt()
        do {
            CloudKitBriefingNotificationMode.save(mode)
            try await CloudKitService.shared.createOrUpdateSubscriptions(mode: mode)
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
    static let localNotificationDeliveryErrorDefaultsKey = "pavbot.lastLocalNotificationDeliveryError"
    static let registrationStatusDefaultsKey = "pavbot.lastRemoteNotificationRegistrationStatus"
    static let lastRegisteredAtDefaultsKey = "pavbot.lastRemoteNotificationRegisteredAt"
    static let apnsEnvironmentDefaultsKey = "pavbot.apnsEnvironment"
    static let lastCloudKitPushReceivedAtDefaultsKey = "pavbot.lastCloudKitPushReceivedAt"
    static let lastCloudKitPushSubscriptionIDDefaultsKey = "pavbot.lastCloudKitPushSubscriptionID"
    static let lastCloudKitPushModeDefaultsKey = "pavbot.lastCloudKitPushMode"
    static let lastCloudKitPushPayloadKindDefaultsKey = "pavbot.lastCloudKitPushPayloadKind"

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

    static func saveLocalNotificationDeliveryError(_ message: String, defaults: UserDefaults = .standard) {
        if message.isEmpty {
            clearLocalNotificationDeliveryError(defaults: defaults)
        } else {
            defaults.set(message, forKey: localNotificationDeliveryErrorDefaultsKey)
        }
    }

    static func localNotificationDeliveryError(defaults: UserDefaults = .standard) -> String {
        defaults.string(forKey: localNotificationDeliveryErrorDefaultsKey) ?? ""
    }

    static func clearLocalNotificationDeliveryError(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: localNotificationDeliveryErrorDefaultsKey)
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

    static func saveCloudKitPush(
        userInfo: [AnyHashable: Any],
        subscriptionID: String?,
        defaults: UserDefaults = .standard
    ) {
        guard CloudKitService.isBriefingsReadySubscriptionID(subscriptionID) else { return }

        let mode = CloudKitBriefingNotificationMode.mode(forSubscriptionID: subscriptionID)?.title ?? "Legacy / nieznany"
        defaults.set(ISO8601DateFormatter().string(from: Date()), forKey: lastCloudKitPushReceivedAtDefaultsKey)
        defaults.set(subscriptionID ?? "Nieznany", forKey: lastCloudKitPushSubscriptionIDDefaultsKey)
        defaults.set(mode, forKey: lastCloudKitPushModeDefaultsKey)
        defaults.set(cloudKitPayloadKind(userInfo: userInfo), forKey: lastCloudKitPushPayloadKindDefaultsKey)
    }

    static func lastCloudKitPushSummary(defaults: UserDefaults = .standard) -> String {
        guard let receivedAt = defaults.string(forKey: lastCloudKitPushReceivedAtDefaultsKey), !receivedAt.isEmpty else {
            return "Brak"
        }
        let mode = defaults.string(forKey: lastCloudKitPushModeDefaultsKey) ?? "Nieznany"
        let kind = defaults.string(forKey: lastCloudKitPushPayloadKindDefaultsKey) ?? "Nieznany"
        let subscriptionID = defaults.string(forKey: lastCloudKitPushSubscriptionIDDefaultsKey) ?? "Nieznany"
        return "\(receivedAt) · \(mode) · \(kind) · \(subscriptionID)"
    }

    private static func cloudKitPayloadKind(userInfo: [AnyHashable: Any]) -> String {
        guard let aps = userInfo["aps"] as? [String: Any] else {
            return "Nieznany"
        }

        let hasVisibleAlert = aps["alert"] != nil || aps["sound"] != nil
        let hasBackgroundRefresh: Bool
        if let value = aps["content-available"] as? Int {
            hasBackgroundRefresh = value == 1
        } else if let value = aps["content-available"] as? Bool {
            hasBackgroundRefresh = value
        } else {
            hasBackgroundRefresh = false
        }

        switch (hasVisibleAlert, hasBackgroundRefresh) {
        case (true, true):
            return "Alert + odświeżenie"
        case (true, false):
            return "Alert"
        case (false, true):
            return "Ciche odświeżenie"
        case (false, false):
            return "Nieznany"
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
        let cloudKitNotification = CKNotification(fromRemoteNotificationDictionary: userInfo)
        RemoteNotificationDiagnostics.saveCloudKitPush(userInfo: userInfo, subscriptionID: cloudKitNotification?.subscriptionID)
        let command = NotificationRoutingCommand(userInfo: userInfo)
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
           CloudKitService.isBriefingsReadySubscriptionID(queryNotification.subscriptionID) {
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
        RemoteNotificationDiagnostics.saveRegistrationError("APNs registration failed: \(error.localizedDescription)")
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        Task { @MainActor in
            let cloudKitNotification = CKNotification(fromRemoteNotificationDictionary: userInfo)
            RemoteNotificationDiagnostics.saveCloudKitPush(userInfo: userInfo, subscriptionID: cloudKitNotification?.subscriptionID)
            if CloudKitService.isBriefingsReadySubscriptionID(cloudKitNotification?.subscriptionID) {
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
