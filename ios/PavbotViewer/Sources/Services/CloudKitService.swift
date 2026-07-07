import CloudKit
import Foundation
import os
import UIKit

enum CloudKitConfiguration {
    static let containerIdentifier = PavbotConnectionDefaults.cloudKitContainerIdentifier
}

enum CloudKitRuntimeSupport {
    static let disabledInUnitTestsMessage = "CloudKit runtime is disabled in the unit-test host."
    static let missingEntitlementsMessage = "CloudKit runtime is disabled because the signed app is missing the Pavbot iCloud container entitlement."
    private static let iCloudServicesEntitlement = "com.apple.developer.icloud-services"
    private static let iCloudContainersEntitlement = "com.apple.developer.icloud-container-identifiers"

    static var isRunningUnitTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || NSClassFromString("XCTestCase") != nil
            || ProcessInfo.processInfo.arguments.contains { $0.localizedCaseInsensitiveContains("xctest") }
    }

    static func shouldUseCloudKitRuntime() -> Bool {
        !isRunningUnitTests
    }

    static func requireCloudKitRuntime() throws {
        guard !isRunningUnitTests else {
            throw CloudKitRuntimeError.disabledInUnitTests
        }
    }

    static func entitlementsSupportCloudKit(
        _ entitlements: [String: Any],
        containerIdentifier: String = CloudKitConfiguration.containerIdentifier
    ) -> Bool {
        let services = stringArrayEntitlement(iCloudServicesEntitlement, in: entitlements)
        let containers = stringArrayEntitlement(iCloudContainersEntitlement, in: entitlements)
        return services.contains("CloudKit") && containers.contains(containerIdentifier)
    }

    private static func stringArrayEntitlement(_ key: String, in entitlements: [String: Any]) -> [String] {
        if let values = entitlements[key] as? [String] {
            return values
        }
        if let value = entitlements[key] as? String {
            return [value]
        }
        if let values = entitlements[key] as? NSArray {
            return values.compactMap { $0 as? String }
        }
        return []
    }
}

enum CloudKitRuntimeError: LocalizedError, Equatable {
    case disabledInUnitTests
    case missingEntitlements

    var errorDescription: String? {
        switch self {
        case .disabledInUnitTests:
            CloudKitRuntimeSupport.disabledInUnitTestsMessage
        case .missingEntitlements:
            CloudKitRuntimeSupport.missingEntitlementsMessage
        }
    }
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

protocol BriefingMetadataFetching: Sendable {
    func fetchLatestBriefings(limit: Int) async throws -> [Briefing]
    func fetchBriefing(by briefingId: String) async throws -> Briefing
    func createOrUpdateSubscriptions() async throws
}

actor CloudKitService: BriefingMetadataFetching, GeneratedPackageRemoteFetching {
    static let shared = CloudKitService()
    static let briefingsReadySubscriptionID = "briefings-ready-subscription"

    private let containerIdentifier: String
    private let logger: Logger

    private var container: CKContainer {
        CKContainer(identifier: containerIdentifier)
    }
    private var publicCloudDatabase: CKDatabase {
        container.publicCloudDatabase
    }
    private var privateCloudDatabase: CKDatabase {
        container.privateCloudDatabase
    }

    init(containerIdentifier: String = CloudKitConfiguration.containerIdentifier) {
        self.containerIdentifier = containerIdentifier
        logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "PavbotViewer", category: "CloudKit")
    }

    func fetchLatestGeneratedPackage() async throws -> GeneratedPackage {
        do {
            try CloudKitRuntimeSupport.requireCloudKitRuntime()
            let predicate = NSPredicate(format: "status == %@", "ready")
            let query = CKQuery(recordType: "GeneratedPackage", predicate: predicate)
            query.sortDescriptors = [NSSortDescriptor(key: "generatedAt", ascending: false)]
            let (matches, _) = try await publicCloudDatabase.records(matching: query, resultsLimit: 1)
            guard let first = matches.first else {
                throw CloudKitRecordMappingError.missingRecord(
                    recordType: "GeneratedPackage",
                    field: "status",
                    value: "ready"
                )
            }
            return try await generatedPackage(from: first.1.get())
        } catch {
            logger.error("CloudKit generated package fetch failed: \(Self.logMessage(for: error), privacy: .public)")
            throw error
        }
    }

    func fetchLatestBriefings(limit: Int = 50) async throws -> [Briefing] {
        do {
            try CloudKitRuntimeSupport.requireCloudKitRuntime()
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
            try CloudKitRuntimeSupport.requireCloudKitRuntime()
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

    func saveUserNotificationPreferences(_ preferences: UserNotificationPreferences) async throws {
        try CloudKitRuntimeSupport.requireCloudKitRuntime()
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
            try CloudKitRuntimeSupport.requireCloudKitRuntime()
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

    func createOrUpdateSubscriptions() async throws {
        try CloudKitRuntimeSupport.requireCloudKitRuntime()
        let predicate = NSPredicate(format: "status == %@", "ready")
        let subscription = CKQuerySubscription(
            recordType: Briefing.recordType,
            predicate: predicate,
            subscriptionID: Self.briefingsReadySubscriptionID,
            options: [.firesOnRecordCreation, .firesOnRecordUpdate]
        )
        let notificationInfo = CKSubscription.NotificationInfo()
        notificationInfo.titleLocalizationKey = "Pavbot"
        notificationInfo.subtitleLocalizationKey = "%@"
        notificationInfo.subtitleLocalizationArgs = ["title"]
        notificationInfo.alertLocalizationKey = "Nowe dane: %@"
        notificationInfo.alertLocalizationArgs = ["title"]
        notificationInfo.soundName = "default"
        notificationInfo.desiredKeys = ["briefingId", "title", "summary", "manifestUrl", "category", "createdAt"]
        notificationInfo.shouldSendContentAvailable = true
        subscription.notificationInfo = notificationInfo

        do {
            try await withCheckedThrowingContinuation { continuation in
                let operation = CKModifySubscriptionsOperation(
                    subscriptionsToSave: [subscription],
                    subscriptionIDsToDelete: []
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
            logger.info("CloudKit subscription \(Self.briefingsReadySubscriptionID, privacy: .public) is ready.")
        } catch {
            logger.error("CloudKit subscription update failed: \(Self.logMessage(for: error), privacy: .public)")
            throw error
        }
    }

    private static func logMessage(for error: Error) -> String {
        if let ckError = error as? CKError {
            return "\(ckError.code): \(ckError.localizedDescription)"
        }
        return error.localizedDescription
    }

    private func generatedPackage(from record: CKRecord) async throws -> GeneratedPackage {
        let packageId = record["packageId"] as? String
        let environment = (record["environment"] as? String)
            .flatMap(GeneratedPackageEnvironment.init(rawValue:))
        let manifestURLString = record["manifestUrl"] as? String ?? record["manifestURL"] as? String

        if let manifest = try decodeEmbeddedManifest(from: record) {
            return GeneratedPackage(
                manifest: manifest,
                manifestURL: manifestURLString.flatMap(URL.init(string:)),
                source: .cloudKit,
                packageId: packageId,
                environment: environment
            )
        }

        guard
            let manifestURLString,
            let manifestURL = URL(string: manifestURLString)
        else {
            throw CloudKitRecordMappingError.missingField(recordType: record.recordType, field: "manifestJSON|manifestUrl")
        }

        let manifest = try await ManifestClient().fetchManifest(from: manifestURL)
        return GeneratedPackage(
            manifest: manifest,
            manifestURL: manifestURL,
            source: .cloudKit,
            packageId: packageId,
            environment: environment
        )
    }

    private func decodeEmbeddedManifest(from record: CKRecord) throws -> PavbotManifest? {
        if let manifestJSON = record["manifestJSON"] as? String ?? record["manifestJson"] as? String {
            guard let data = manifestJSON.data(using: .utf8) else {
                throw CloudKitRecordMappingError.missingField(recordType: record.recordType, field: "manifestJSON")
            }
            return try JSONDecoder.pavbot.decode(PavbotManifest.self, from: data)
        }

        if let data = record["manifestData"] as? Data {
            return try JSONDecoder.pavbot.decode(PavbotManifest.self, from: data)
        }

        return nil
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
            notification.subscriptionID == CloudKitService.briefingsReadySubscriptionID
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
