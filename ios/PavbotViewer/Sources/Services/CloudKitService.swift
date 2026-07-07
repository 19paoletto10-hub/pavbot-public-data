import CloudKit
import Foundation
import os
import UIKit

enum CloudKitConfiguration {
    static let containerIdentifier = PavbotConnectionDefaults.cloudKitContainerIdentifier
}

struct Briefing: Identifiable, Equatable, Sendable {
    static let recordType = "Briefing"

    var id: String { briefingId }

    let briefingId: String
    let title: String
    let summary: String
    let manifestUrl: String
    let audioUrl: String?
    let imageUrl: String?
    let createdAt: Date
    let locale: String
    let category: String?
    let status: String
    let version: Int

    init(
        briefingId: String,
        title: String,
        summary: String,
        manifestUrl: String,
        audioUrl: String? = nil,
        imageUrl: String? = nil,
        createdAt: Date,
        locale: String,
        category: String? = nil,
        status: String = "ready",
        version: Int = 1
    ) {
        self.briefingId = briefingId
        self.title = title
        self.summary = summary
        self.manifestUrl = manifestUrl
        self.audioUrl = audioUrl
        self.imageUrl = imageUrl
        self.createdAt = createdAt
        self.locale = locale
        self.category = category
        self.status = status
        self.version = version
    }

    init(record: CKRecord) throws {
        briefingId = try Self.requiredString("briefingId", in: record)
        title = try Self.requiredString("title", in: record)
        summary = try Self.requiredString("summary", in: record)
        manifestUrl = try Self.requiredString("manifestUrl", in: record)
        audioUrl = record["audioUrl"] as? String
        imageUrl = record["imageUrl"] as? String
        createdAt = try Self.requiredDate("createdAt", in: record)
        locale = try Self.requiredString("locale", in: record)
        category = record["category"] as? String
        status = try Self.requiredString("status", in: record)
        version = try Self.requiredInt("version", in: record)
    }

    func record(recordID: CKRecord.ID? = nil) -> CKRecord {
        let record = CKRecord(
            recordType: Self.recordType,
            recordID: recordID ?? CKRecord.ID(recordName: briefingId)
        )
        apply(to: record)
        return record
    }

    func apply(to record: CKRecord) {
        record["briefingId"] = briefingId as CKRecordValue
        record["title"] = title as CKRecordValue
        record["summary"] = summary as CKRecordValue
        record["manifestUrl"] = manifestUrl as CKRecordValue
        record["audioUrl"] = audioUrl as CKRecordValue?
        record["imageUrl"] = imageUrl as CKRecordValue?
        record["createdAt"] = createdAt as CKRecordValue
        record["locale"] = locale as CKRecordValue
        record["category"] = category as CKRecordValue?
        record["status"] = status as CKRecordValue
        record["version"] = version as CKRecordValue
    }

    private static func requiredString(_ key: String, in record: CKRecord) throws -> String {
        guard let value = record[key] as? String, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CloudKitRecordMappingError.missingField(recordType: record.recordType, field: key)
        }
        return value
    }

    private static func requiredDate(_ key: String, in record: CKRecord) throws -> Date {
        guard let value = record[key] as? Date else {
            throw CloudKitRecordMappingError.missingField(recordType: record.recordType, field: key)
        }
        return value
    }

    private static func requiredInt(_ key: String, in record: CKRecord) throws -> Int {
        if let value = record[key] as? Int {
            return value
        }
        if let value = record[key] as? Int64 {
            return Int(value)
        }
        throw CloudKitRecordMappingError.missingField(recordType: record.recordType, field: key)
    }
}

struct CloudKitArtifact: Identifiable, Equatable, Sendable {
    static let recordType = "Artifact"

    var id: String { artifactId }

    let artifactId: String
    let briefingId: String
    let topic: String
    let stamp: String
    let type: String
    let title: String
    let path: String
    let url: String
    let sizeBytes: Int
    let date: String?
    let time: String?
    let manifestUrl: String
    let status: String
    let createdAt: Date
    let version: Int

    init(record: CKRecord) throws {
        artifactId = try Self.requiredString("artifactId", in: record)
        briefingId = try Self.requiredString("briefingId", in: record)
        topic = try Self.requiredString("topic", in: record)
        stamp = try Self.requiredString("stamp", in: record)
        type = try Self.requiredString("type", in: record)
        title = try Self.requiredString("title", in: record)
        path = try Self.requiredString("path", in: record)
        url = try Self.requiredString("url", in: record)
        sizeBytes = try Self.requiredInt("sizeBytes", in: record)
        date = Self.optionalString("date", in: record)
        time = Self.optionalString("time", in: record)
        manifestUrl = try Self.requiredString("manifestUrl", in: record)
        status = try Self.requiredString("status", in: record)
        createdAt = try Self.requiredDate("createdAt", in: record)
        version = try Self.requiredInt("version", in: record)
    }

    private static func optionalString(_ key: String, in record: CKRecord) -> String? {
        guard let value = record[key] as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : value
    }

    private static func requiredString(_ key: String, in record: CKRecord) throws -> String {
        guard let value = record[key] as? String, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CloudKitRecordMappingError.missingField(recordType: record.recordType, field: key)
        }
        return value
    }

    private static func requiredDate(_ key: String, in record: CKRecord) throws -> Date {
        guard let value = record[key] as? Date else {
            throw CloudKitRecordMappingError.missingField(recordType: record.recordType, field: key)
        }
        return value
    }

    private static func requiredInt(_ key: String, in record: CKRecord) throws -> Int {
        if let value = record[key] as? Int {
            return value
        }
        if let value = record[key] as? Int64 {
            return Int(value)
        }
        throw CloudKitRecordMappingError.missingField(recordType: record.recordType, field: key)
    }
}

struct UserNotificationPreferences: Equatable, Sendable {
    static let recordType = "UserPreferences"
    static let recordName = "current-user-preferences"

    var preferredLocale: String
    var city: String?
    var notificationHour: Int?
    var enabledCategories: [String]
    var notificationsEnabled: Bool

    static let defaults = UserNotificationPreferences(
        preferredLocale: Locale.current.identifier,
        city: nil,
        notificationHour: nil,
        enabledCategories: [],
        notificationsEnabled: false
    )

    init(
        preferredLocale: String,
        city: String?,
        notificationHour: Int?,
        enabledCategories: [String],
        notificationsEnabled: Bool
    ) {
        self.preferredLocale = preferredLocale
        self.city = city
        self.notificationHour = notificationHour
        self.enabledCategories = enabledCategories
        self.notificationsEnabled = notificationsEnabled
    }

    init(record: CKRecord) throws {
        preferredLocale = record["preferredLocale"] as? String ?? Locale.current.identifier
        city = record["city"] as? String
        if let hour = record["notificationHour"] as? Int {
            notificationHour = hour
        } else if let hour = record["notificationHour"] as? Int64 {
            notificationHour = Int(hour)
        } else {
            notificationHour = nil
        }
        enabledCategories = record["enabledCategories"] as? [String] ?? []
        if let value = record["notificationsEnabled"] as? Bool {
            notificationsEnabled = value
        } else if let value = record["notificationsEnabled"] as? Int64 {
            notificationsEnabled = value != 0
        } else if let value = record["notificationsEnabled"] as? Int {
            notificationsEnabled = value != 0
        } else {
            notificationsEnabled = false
        }
    }

    func record(existing: CKRecord? = nil) -> CKRecord {
        let record = existing ?? CKRecord(
            recordType: Self.recordType,
            recordID: CKRecord.ID(recordName: Self.recordName)
        )
        record["preferredLocale"] = preferredLocale as CKRecordValue
        record["city"] = city as CKRecordValue?
        record["notificationHour"] = notificationHour as CKRecordValue?
        record["enabledCategories"] = enabledCategories as CKRecordValue
        record["notificationsEnabled"] = notificationsEnabled as CKRecordValue
        return record
    }
}

enum CloudKitRecordMappingError: LocalizedError, Equatable {
    case missingField(recordType: String, field: String)
    case missingRecord(recordType: String, field: String, value: String)

    var errorDescription: String? {
        switch self {
        case .missingField(let recordType, let field):
            "CloudKit \(recordType) record is missing required field \(field)."
        case .missingRecord(let recordType, let field, let value):
            "CloudKit \(recordType) record was not found for \(field)=\(value)."
        }
    }
}

enum CloudKitBriefingNotificationMode: String, CaseIterable, Identifiable, Sendable {
    case visibleAlert
    case silentRefresh

    static let defaultsKey = "pavbot.cloudKitBriefingNotificationMode"
    static let defaultValue: Self = .visibleAlert

    var id: String { rawValue }

    var title: String {
        switch self {
        case .visibleAlert:
            "Widoczny alert"
        case .silentRefresh:
            "Ciche odświeżenie"
        }
    }

    var detail: String {
        switch self {
        case .visibleAlert:
            "Pokazuje baner z dźwiękiem i odświeża manifest po publikacji briefingu."
        case .silentRefresh:
            "Odświeża dane w tle bez banera i dźwięku."
        }
    }

    var subscriptionID: String {
        switch self {
        case .visibleAlert:
            "briefings-ready-visible-alert-subscription-v2"
        case .silentRefresh:
            "briefings-ready-silent-refresh-subscription-v1"
        }
    }

    static func load(defaults: UserDefaults = .standard) -> Self {
        guard let rawValue = defaults.string(forKey: defaultsKey), let mode = Self(rawValue: rawValue) else {
            return defaultValue
        }
        return mode
    }

    static func save(_ mode: Self, defaults: UserDefaults = .standard) {
        defaults.set(mode.rawValue, forKey: defaultsKey)
    }

    static func mode(forSubscriptionID subscriptionID: String?) -> Self? {
        guard let subscriptionID else { return nil }
        return allCases.first { $0.subscriptionID == subscriptionID }
    }
}

protocol BriefingMetadataFetching: Sendable {
    func fetchLatestBriefings(limit: Int) async throws -> [Briefing]
    func fetchBriefing(by briefingId: String) async throws -> Briefing
    func fetchArtifacts(for briefingId: String) async throws -> [CloudKitArtifact]
    func createOrUpdateSubscriptions(mode: CloudKitBriefingNotificationMode) async throws
}

actor CloudKitService: BriefingMetadataFetching {
    static let shared = CloudKitService()
    static let legacyBriefingsReadySubscriptionID = "briefings-ready-subscription"
    static let briefingNotificationDesiredKeys = ["briefingId", "title", "summary", "manifestUrl", "category", "createdAt"]

    private let container: CKContainer
    private let publicCloudDatabase: CKDatabase
    private let privateCloudDatabase: CKDatabase
    private let logger: Logger

    init(containerIdentifier: String = CloudKitConfiguration.containerIdentifier) {
        container = CKContainer(identifier: containerIdentifier)
        publicCloudDatabase = container.publicCloudDatabase
        privateCloudDatabase = container.privateCloudDatabase
        logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "PavbotViewer", category: "CloudKit")
    }

    func fetchLatestBriefings(limit: Int = 50) async throws -> [Briefing] {
        do {
            let predicate = NSPredicate(format: "status == %@", "ready")
            let query = CKQuery(recordType: Briefing.recordType, predicate: predicate)
            query.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
            let (matches, _) = try await publicCloudDatabase.records(matching: query, resultsLimit: limit)
            let briefings = try matches.map { _, result in
                try Briefing(record: result.get())
            }
            logger.info("Fetched \(briefings.count, privacy: .public) ready CloudKit briefings.")
            return briefings
        } catch {
            logger.error("CloudKit latest briefing fetch failed: \(Self.logMessage(for: error), privacy: .public)")
            throw error
        }
    }

    func fetchBriefing(by briefingId: String) async throws -> Briefing {
        do {
            let predicate = NSPredicate(format: "briefingId == %@", briefingId)
            let query = CKQuery(recordType: Briefing.recordType, predicate: predicate)
            let (matches, _) = try await publicCloudDatabase.records(matching: query, resultsLimit: 1)
            guard let first = matches.first else {
                throw CloudKitRecordMappingError.missingRecord(
                    recordType: Briefing.recordType,
                    field: "briefingId",
                    value: briefingId
                )
            }
            return try Briefing(record: first.1.get())
        } catch {
            logger.error("CloudKit briefing fetch failed for \(briefingId, privacy: .public): \(Self.logMessage(for: error), privacy: .public)")
            throw error
        }
    }

    func fetchArtifacts(for briefingId: String) async throws -> [CloudKitArtifact] {
        do {
            let predicate = NSPredicate(value: true)
            let query = CKQuery(recordType: CloudKitArtifact.recordType, predicate: predicate)
            let (matches, _) = try await publicCloudDatabase.records(matching: query, resultsLimit: 200)
            let artifacts = try matches.map { _, result in
                try CloudKitArtifact(record: result.get())
            }.filter { artifact in
                artifact.briefingId == briefingId
            }.sorted { $0.path < $1.path }
            logger.info("Fetched \(artifacts.count, privacy: .public) CloudKit artifacts for \(briefingId, privacy: .public).")
            return artifacts
        } catch {
            logger.error("CloudKit artifact fetch failed for \(briefingId, privacy: .public): \(Self.logMessage(for: error), privacy: .public)")
            throw error
        }
    }

    func saveUserNotificationPreferences(_ preferences: UserNotificationPreferences) async throws {
        do {
            let existing = try? await privateCloudDatabase.record(
                for: CKRecord.ID(recordName: UserNotificationPreferences.recordName)
            )
            _ = try await privateCloudDatabase.save(preferences.record(existing: existing))
            logger.info("Saved CloudKit user notification preferences.")
        } catch {
            logger.error("CloudKit preference save failed: \(Self.logMessage(for: error), privacy: .public)")
            throw error
        }
    }

    func loadUserNotificationPreferences() async throws -> UserNotificationPreferences {
        do {
            let record = try await privateCloudDatabase.record(
                for: CKRecord.ID(recordName: UserNotificationPreferences.recordName)
            )
            return try UserNotificationPreferences(record: record)
        } catch let error as CKError where error.code == .unknownItem {
            logger.info("CloudKit user preferences are not created yet; using defaults.")
            return .defaults
        } catch {
            logger.error("CloudKit preference load failed: \(Self.logMessage(for: error), privacy: .public)")
            throw error
        }
    }

    func createOrUpdateSubscriptions(mode: CloudKitBriefingNotificationMode = .load()) async throws {
        let subscription = Self.briefingSubscription(for: mode)

        do {
            try await withCheckedThrowingContinuation { continuation in
                let operation = CKModifySubscriptionsOperation(
                    subscriptionsToSave: [subscription],
                    subscriptionIDsToDelete: Self.inactiveBriefingSubscriptionIDs(for: mode)
                )
                operation.modifySubscriptionsResultBlock = { result in
                    switch result {
                    case .success:
                        continuation.resume()
                    case .failure(let error):
                        continuation.resume(throwing: error)
                    }
                }
                publicCloudDatabase.add(operation)
            }
            logger.info("CloudKit subscription \(mode.subscriptionID, privacy: .public) is ready for \(mode.title, privacy: .public).")
        } catch {
            logger.error("CloudKit subscription update failed: \(Self.logMessage(for: error), privacy: .public)")
            throw error
        }
    }

    static func briefingSubscription(for mode: CloudKitBriefingNotificationMode) -> CKQuerySubscription {
        let predicate = NSPredicate(format: "status == %@", "ready")
        let subscription = CKQuerySubscription(
            recordType: Briefing.recordType,
            predicate: predicate,
            subscriptionID: mode.subscriptionID,
            options: [.firesOnRecordCreation, .firesOnRecordUpdate]
        )
        subscription.notificationInfo = briefingNotificationInfo(for: mode)
        return subscription
    }

    static func briefingNotificationInfo(for mode: CloudKitBriefingNotificationMode) -> CKSubscription.NotificationInfo {
        let notificationInfo = CKSubscription.NotificationInfo()
        switch mode {
        case .visibleAlert:
            notificationInfo.titleLocalizationKey = "PAVBOT_BRIEFING_NOTIFICATION_TITLE"
            notificationInfo.alertLocalizationKey = "PAVBOT_BRIEFING_NOTIFICATION_BODY"
            notificationInfo.alertLocalizationArgs = ["title"]
            notificationInfo.soundName = "default"
            notificationInfo.shouldSendContentAvailable = true
        case .silentRefresh:
            notificationInfo.shouldSendContentAvailable = true
        }
        notificationInfo.desiredKeys = Self.briefingNotificationDesiredKeys
        return notificationInfo
    }

    static func inactiveBriefingSubscriptionIDs(for mode: CloudKitBriefingNotificationMode) -> [String] {
        [legacyBriefingsReadySubscriptionID] + CloudKitBriefingNotificationMode.allCases
            .filter { $0 != mode }
            .map(\.subscriptionID)
    }

    static func isBriefingsReadySubscriptionID(_ subscriptionID: String?) -> Bool {
        guard let subscriptionID else { return false }
        if subscriptionID == legacyBriefingsReadySubscriptionID {
            return true
        }
        return CloudKitBriefingNotificationMode.allCases.contains { $0.subscriptionID == subscriptionID }
    }

    private static func logMessage(for error: Error) -> String {
        if let ckError = error as? CKError {
            return "\(ckError.code): \(ckError.localizedDescription)"
        }
        return error.localizedDescription
    }
}

@MainActor
final class CloudKitPushRefreshCenter {
    static let shared = CloudKitPushRefreshCenter()

    private var refreshHandler: (() async -> Void)?
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "PavbotViewer", category: "CloudKitPush")

    private init() {}

    func installRefreshHandler(_ handler: @escaping () async -> Void) {
        refreshHandler = handler
    }

    func handleRemoteNotification(_ userInfo: [AnyHashable: Any]) async -> UIBackgroundFetchResult {
        guard
            let notification = CKNotification(fromRemoteNotificationDictionary: userInfo),
            CloudKitService.isBriefingsReadySubscriptionID(notification.subscriptionID)
        else {
            logger.debug("Ignoring non-Pavbot CloudKit push.")
            return .noData
        }

        guard let refreshHandler else {
            logger.error("Received Pavbot CloudKit push before refresh handler was installed.")
            return .noData
        }
        logger.info("Received Pavbot CloudKit push; refreshing manifest.")
        await refreshHandler()
        return .newData
    }
}
