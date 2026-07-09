import AVFoundation
import Combine
import CryptoKit
import Foundation
import Observation

struct AutomationTranslationKey: Hashable {
    let sourceLanguage: String
    let targetLanguage: String
    let sourceText: String

    var id: String {
        "\(sourceLanguage)::\(targetLanguage)::\(sourceText)"
    }

    var persistentID: String {
        let hash = AutomationTranslationHasher.sha256(sourceText)
        return "\(sourceLanguage)::\(targetLanguage)::\(hash)"
    }
}

struct AutomationTranslationRequest: Identifiable, Equatable {
    let key: AutomationTranslationKey
    let sourceText: String
    let sourceLanguageCode: String?
    let targetLanguageCode: String
    let documentID: String?
    let fieldPath: String?

    var id: String { key.id }

    init(
        key: AutomationTranslationKey,
        sourceText: String,
        sourceLanguageCode: String?,
        targetLanguageCode: String,
        documentID: String? = nil,
        fieldPath: String? = nil
    ) {
        self.key = key
        self.sourceText = sourceText
        self.sourceLanguageCode = sourceLanguageCode
        self.targetLanguageCode = targetLanguageCode
        self.documentID = documentID
        self.fieldPath = fieldPath
    }
}

enum AutomationTranslationState: String, Codable, Equatable, Hashable {
    case queued
    case preparing
    case translated
    case failed
    case unsupported
}

struct AutomationTranslationField: Codable, Equatable, Hashable {
    let path: String
    let sourceText: String
    let sourceLanguageCode: String?

    init(path: String, sourceText: String, sourceLanguageCode: String? = "pl") {
        self.path = path
        self.sourceText = sourceText
        self.sourceLanguageCode = sourceLanguageCode
    }

    var trimmedSourceText: String {
        sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct AutomationTranslationDocument: Codable, Equatable, Identifiable {
    let contentKind: String
    let contentID: String
    let sourceLanguage: String
    let fields: [AutomationTranslationField]
    let sourceHash: String

    var id: String {
        [contentKind, contentID, sourceHash].joined(separator: "::")
    }

    init(
        contentKind: String,
        contentID: String,
        sourceLanguage: String = "pl",
        fields: [AutomationTranslationField]
    ) {
        self.contentKind = contentKind
        self.contentID = contentID
        self.sourceLanguage = sourceLanguage
        self.fields = Self.normalizedFields(fields)
        self.sourceHash = Self.sourceHash(for: self.fields)
    }

    func bundleID(targetLanguage: AppLanguagePreference) -> String {
        [
            contentKind,
            contentID,
            sourceHash,
            sourceLanguage,
            targetLanguage.rawValue
        ]
        .joined(separator: "::")
    }

    private static func normalizedFields(_ fields: [AutomationTranslationField]) -> [AutomationTranslationField] {
        var seen = Set<String>()
        return fields.compactMap { field in
            let path = field.path.trimmingCharacters(in: .whitespacesAndNewlines)
            let text = field.trimmedSourceText
            guard !path.isEmpty, !text.isEmpty, seen.insert(path).inserted else { return nil }
            return AutomationTranslationField(
                path: path,
                sourceText: text,
                sourceLanguageCode: field.sourceLanguageCode
            )
        }
    }

    private static func sourceHash(for fields: [AutomationTranslationField]) -> String {
        let source = fields
            .sorted { $0.path < $1.path }
            .map { field in
                [
                    field.path,
                    field.sourceLanguageCode ?? "auto",
                    field.trimmedSourceText
                ]
                .joined(separator: "\u{1f}")
            }
            .joined(separator: "\u{1e}")
        return AutomationTranslationHasher.sha256(source)
    }
}

struct AutomationTranslationBundle: Codable, Equatable, Identifiable {
    let id: String
    let contentKind: String
    let contentID: String
    let sourceHash: String
    let sourceLanguage: String
    let targetLanguage: String
    var translations: [String: String]
    var fieldStates: [String: AutomationTranslationState]
    var updatedAt: Date

    init(document: AutomationTranslationDocument, targetLanguage: AppLanguagePreference) {
        self.id = document.bundleID(targetLanguage: targetLanguage)
        self.contentKind = document.contentKind
        self.contentID = document.contentID
        self.sourceHash = document.sourceHash
        self.sourceLanguage = document.sourceLanguage
        self.targetLanguage = targetLanguage.rawValue
        self.translations = [:]
        self.fieldStates = [:]
        self.updatedAt = Date()
    }
}

struct AutomationTranslationResolution: Equatable {
    let text: String
    let state: AutomationTranslationState
    let usedSourceFallback: Bool

    var isTranslated: Bool {
        state == .translated && !usedSourceFallback
    }
}

enum AutomationTranslationHasher {
    static func sha256(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

@MainActor
@Observable
final class AutomationTranslationStore {
    typealias Translator = @MainActor (_ sourceText: String, _ targetLanguageCode: String) async -> String

    private(set) var pendingRevision = 0

    @ObservationIgnored private let fileManager: FileManager
    @ObservationIgnored private let translationsDirectory: URL
    @ObservationIgnored private var cachedTranslations: [AutomationTranslationKey: String] = [:]
    @ObservationIgnored private var registeredDocuments: [String: AutomationTranslationDocument] = [:]
    @ObservationIgnored private var bundles: [String: AutomationTranslationBundle] = [:]
    @ObservationIgnored private var requestStates: [AutomationTranslationKey: AutomationTranslationState] = [:]
    @ObservationIgnored private var pendingRequests: [AutomationTranslationRequest] = []
    @ObservationIgnored private var inFlightKeys: Set<AutomationTranslationKey> = []
    @ObservationIgnored private var waiters: [AutomationTranslationKey: [CheckedContinuation<String, Never>]] = [:]
    @ObservationIgnored private var requiredWaiters: [AutomationTranslationKey: [CheckedContinuation<AutomationTranslationResolution, Never>]] = [:]
    @ObservationIgnored private var dirtyBundleIDs: Set<String> = []
    @ObservationIgnored private var bundleSaveTask: Task<Void, Never>?

    init(
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default,
        translationsDirectory: URL? = nil
    ) {
        _ = defaults
        self.fileManager = fileManager
        self.translationsDirectory = translationsDirectory ?? Self.defaultTranslationsDirectory(fileManager: fileManager)
    }

    func displayText(_ sourceText: String, language: AppLanguagePreference) -> String {
        guard let request = request(for: sourceText, language: language) else { return sourceText }
        return cachedTranslation(for: request) ?? sourceText
    }

    func displayExternalText(_ sourceText: String, language: AppLanguagePreference) -> String {
        guard let request = externalRequest(for: sourceText, language: language) else { return sourceText }
        return cachedTranslation(for: request) ?? sourceText
    }

    func externalResolution(for sourceText: String, language: AppLanguagePreference) -> AutomationTranslationResolution {
        guard let request = externalRequest(for: sourceText, language: language) else {
            return AutomationTranslationResolution(text: sourceText, state: .translated, usedSourceFallback: false)
        }
        if let cached = cachedTranslation(for: request) {
            return AutomationTranslationResolution(text: cached, state: .translated, usedSourceFallback: false)
        }
        let state = requestStates[request.key] ?? (pendingRequests.contains(where: { $0.key == request.key }) ? .queued : .queued)
        return AutomationTranslationResolution(text: request.sourceText, state: state, usedSourceFallback: true)
    }

    func requestTranslation(for sourceText: String, language: AppLanguagePreference) {
        guard let request = request(for: sourceText, language: language) else { return }
        guard cachedTranslations[request.key] == nil else { return }
        enqueue(request)
    }

    func requestExternalTranslation(for sourceText: String, language: AppLanguagePreference) {
        guard let request = externalRequest(for: sourceText, language: language) else { return }
        guard cachedTranslations[request.key] == nil else { return }
        enqueue(request)
    }

    func register(
        _ document: AutomationTranslationDocument,
        language: AppLanguagePreference,
        eagerPaths: Set<String>? = nil
    ) {
        guard !document.fields.isEmpty else { return }
        registeredDocuments[document.id] = document
        var didChangeBundle = false

        let translatableFields = document.fields.compactMap { field -> (AutomationTranslationField, AutomationTranslationRequest)? in
            guard let request = request(for: field, document: document, language: language) else { return nil }
            return (field, request)
        }
        guard !translatableFields.isEmpty else { return }

        var bundle = loadOrCreateBundle(for: document, language: language)
        for (field, request) in translatableFields {
            if let translated = bundle.translations[field.path]?.trimmingCharacters(in: .whitespacesAndNewlines),
               !translated.isEmpty {
                _ = storeTranslatedText(translated, for: request, persistBundle: false)
                if bundle.fieldStates[field.path] != .translated {
                    bundle.fieldStates[field.path] = .translated
                    didChangeBundle = true
                }
                continue
            }

            if let cached = cachedTranslation(for: request) {
                bundle.translations[field.path] = cached
                if bundle.fieldStates[field.path] != .translated {
                    bundle.fieldStates[field.path] = .translated
                    didChangeBundle = true
                }
                continue
            }

            if bundle.fieldStates[field.path] == .unsupported {
                continue
            }

            if shouldEagerlyQueue(request, eagerPaths: eagerPaths) {
                enqueue(request)
            } else if bundle.fieldStates[field.path] == .queued || bundle.fieldStates[field.path] == .preparing || bundle.fieldStates[field.path] == .failed {
                bundle.fieldStates.removeValue(forKey: field.path)
                didChangeBundle = true
            }
        }
        if didChangeBundle {
            scheduleBundleSave(bundle)
        }
    }

    func requestTranslation(
        for sourceText: String,
        document: AutomationTranslationDocument,
        path: String,
        language: AppLanguagePreference
    ) {
        registeredDocuments[document.id] = document
        guard let field = document.field(path: path) else {
            requestTranslation(for: sourceText, language: language)
            return
        }
        guard let request = request(for: field, document: document, language: language) else { return }

        var bundle = loadOrCreateBundle(for: document, language: language)
        if let translated = bundle.translations[field.path]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !translated.isEmpty {
            _ = storeTranslatedText(translated, for: request, persistBundle: false)
            if bundle.fieldStates[field.path] != .translated {
                bundle.fieldStates[field.path] = .translated
                scheduleBundleSave(bundle)
            }
            return
        }

        if let cached = cachedTranslation(for: request) {
            bundle.translations[field.path] = cached
            bundle.fieldStates[field.path] = .translated
            scheduleBundleSave(bundle)
            return
        }

        if requestStates[request.key] == .unsupported {
            requestStates.removeValue(forKey: request.key)
        }
        enqueue(request)
    }

    func displayText(
        _ sourceText: String,
        document: AutomationTranslationDocument,
        path: String,
        language: AppLanguagePreference
    ) -> String {
        guard let field = document.field(path: path) else {
            return displayText(sourceText, language: language)
        }
        guard let request = request(for: field, document: document, language: language) else {
            return sourceText
        }
        let bundle = loadOrCreateBundle(for: document, language: language)
        if let translated = bundle.translations[field.path]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !translated.isEmpty {
            return translated
        }
        return cachedTranslation(for: request) ?? sourceText
    }

    func resolvedText(
        _ sourceText: String,
        document: AutomationTranslationDocument? = nil,
        path: String? = nil,
        language: AppLanguagePreference
    ) async -> AutomationTranslationResolution {
        if let document, let path, let field = document.field(path: path) {
            registeredDocuments[document.id] = document
            guard let request = request(for: field, document: document, language: language) else {
                return AutomationTranslationResolution(text: sourceText, state: .translated, usedSourceFallback: false)
            }
            if let cached = cachedTranslation(for: request) {
                return AutomationTranslationResolution(text: cached, state: .translated, usedSourceFallback: false)
            }
            if requestStates[request.key] == .unsupported {
                return AutomationTranslationResolution(text: request.sourceText, state: .unsupported, usedSourceFallback: true)
            }
            guard #available(iOS 18.0, *) else {
                return AutomationTranslationResolution(text: sourceText, state: .unsupported, usedSourceFallback: true)
            }
            return await withCheckedContinuation { continuation in
                requiredWaiters[request.key, default: []].append(continuation)
                enqueue(request)
            }
        }

        guard let request = request(for: sourceText, language: language) else {
            return AutomationTranslationResolution(text: sourceText, state: .translated, usedSourceFallback: false)
        }
        if let cached = cachedTranslation(for: request) {
            return AutomationTranslationResolution(text: cached, state: .translated, usedSourceFallback: false)
        }
        if requestStates[request.key] == .unsupported {
            return AutomationTranslationResolution(text: request.sourceText, state: .unsupported, usedSourceFallback: true)
        }
        guard #available(iOS 18.0, *) else {
            return AutomationTranslationResolution(text: sourceText, state: .unsupported, usedSourceFallback: true)
        }
        return await withCheckedContinuation { continuation in
            requiredWaiters[request.key, default: []].append(continuation)
            enqueue(request)
        }
    }

    func resolvedExternalText(
        _ sourceText: String,
        language: AppLanguagePreference
    ) async -> AutomationTranslationResolution {
        guard let request = externalRequest(for: sourceText, language: language) else {
            return AutomationTranslationResolution(text: sourceText, state: .translated, usedSourceFallback: false)
        }
        if let cached = cachedTranslation(for: request) {
            return AutomationTranslationResolution(text: cached, state: .translated, usedSourceFallback: false)
        }
        if requestStates[request.key] == .unsupported {
            return AutomationTranslationResolution(text: request.sourceText, state: .unsupported, usedSourceFallback: true)
        }
        guard #available(iOS 18.0, *) else {
            return AutomationTranslationResolution(text: sourceText, state: .unsupported, usedSourceFallback: true)
        }
        return await withCheckedContinuation { continuation in
            requiredWaiters[request.key, default: []].append(continuation)
            enqueue(request)
        }
    }

    func requiredLocalizedText(
        _ sourceText: String,
        language: AppLanguagePreference,
        document: AutomationTranslationDocument? = nil,
        path: String? = nil,
        translator: Translator? = nil
    ) async -> AutomationTranslationResolution {
        if let document, let path, let field = document.field(path: path) {
            return await requiredLocalizedField(field, document: document, language: language, translator: translator)
        }

        guard let request = request(for: sourceText, language: language) else {
            return AutomationTranslationResolution(text: sourceText, state: .translated, usedSourceFallback: false)
        }
        return await requiredLocalizedText(for: request, language: language, translator: translator)
    }

    func localizedText(
        _ sourceText: String,
        language: AppLanguagePreference,
        translator: Translator? = nil
    ) async -> String {
        guard let request = request(for: sourceText, language: language) else { return sourceText }
        if let cached = cachedTranslation(for: request) {
            return cached
        }
        if requestStates[request.key] == .unsupported {
            return sourceText
        }

        if let translator {
            let translated = await translator(request.sourceText, request.targetLanguageCode)
            let clean = translated.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty else { return sourceText }
            return storeTranslatedText(clean, for: request)
        }

        guard #available(iOS 18.0, *) else { return sourceText }

        return await withCheckedContinuation { continuation in
            waiters[request.key, default: []].append(continuation)
            enqueue(request)
        }
    }

    func nextPendingRequest() -> AutomationTranslationRequest? {
        guard !pendingRequests.isEmpty else { return nil }
        let request = pendingRequests.removeFirst()
        return prepareForProcessing(request)
    }

    func nextPendingBatch(maxCount: Int = 12, maxCharacters: Int = 3_500) -> [AutomationTranslationRequest] {
        guard let first = pendingRequests.first else { return [] }
        return nextPendingBatch(
            sourceLanguageCode: first.sourceLanguageCode,
            targetLanguageCode: first.targetLanguageCode,
            maxCount: maxCount,
            maxCharacters: maxCharacters
        )
    }

    func nextPendingRequest(
        sourceLanguageCode: String?,
        targetLanguageCode: String
    ) -> AutomationTranslationRequest? {
        guard let index = pendingRequests.firstIndex(where: { request in
            request.sourceLanguageCode == sourceLanguageCode
                && request.targetLanguageCode == targetLanguageCode
        }) else {
            return nil
        }
        let request = pendingRequests.remove(at: index)
        return prepareForProcessing(request)
    }

    func nextPendingBatch(
        sourceLanguageCode: String?,
        targetLanguageCode: String,
        maxCount: Int = 12,
        maxCharacters: Int = 3_500
    ) -> [AutomationTranslationRequest] {
        guard maxCount > 0, maxCharacters > 0 else { return [] }

        var selected: [AutomationTranslationRequest] = []
        var selectedIndexes: [Int] = []
        var characterCount = 0

        for (index, request) in pendingRequests.enumerated() {
            guard request.sourceLanguageCode == sourceLanguageCode,
                  request.targetLanguageCode == targetLanguageCode
            else { continue }

            let nextCount = characterCount + request.sourceText.count
            if !selected.isEmpty, (selected.count >= maxCount || nextCount > maxCharacters) {
                break
            }
            selected.append(request)
            selectedIndexes.append(index)
            characterCount = nextCount
            if selected.count >= maxCount {
                break
            }
        }

        for index in selectedIndexes.reversed() {
            pendingRequests.remove(at: index)
        }
        return selected.map(prepareForProcessing)
    }

    func markPreparing(_ request: AutomationTranslationRequest) {
        requestStates[request.key] = .preparing
        updateBundleState(for: request, state: .preparing)
        pendingRevision += 1
    }

    func finish(_ request: AutomationTranslationRequest, translatedText: String) {
        let clean = translatedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else {
            fail(request, reason: "empty translation")
            return
        }
        let resolvedText = storeTranslatedText(clean, for: request)
        inFlightKeys.remove(request.key)
        requestStates[request.key] = .translated
        resumeWaiters(for: request.key, text: resolvedText)
        resumeRequiredWaiters(
            for: request.key,
            resolution: AutomationTranslationResolution(text: resolvedText, state: .translated, usedSourceFallback: false)
        )
        pendingRevision += 1
    }

    func finishBatch(_ translations: [(AutomationTranslationRequest, String)]) {
        guard !translations.isEmpty else { return }
        var dirtyBundlesByID: [String: AutomationTranslationBundle] = [:]

        for (request, translatedText) in translations {
            let clean = translatedText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty else {
                fail(request, reason: "empty translation")
                continue
            }

            cachedTranslations[request.key] = clean
            inFlightKeys.remove(request.key)
            requestStates[request.key] = .translated
            resumeWaiters(for: request.key, text: clean)
            resumeRequiredWaiters(
                for: request.key,
                resolution: AutomationTranslationResolution(text: clean, state: .translated, usedSourceFallback: false)
            )

            if let bundle = bundleUpdatedByTranslation(for: request, translatedText: clean) {
                dirtyBundlesByID[bundle.id] = bundle
            }
        }

        for bundle in dirtyBundlesByID.values {
            scheduleBundleSave(bundle)
        }
        pendingRevision += 1
    }

    func fail(_ request: AutomationTranslationRequest, reason: String? = nil) {
        inFlightKeys.remove(request.key)
        requestStates[request.key] = .failed
        updateBundleState(for: request, state: .failed)
        resumeWaiters(for: request.key, text: request.sourceText)
        resumeRequiredWaiters(
            for: request.key,
            resolution: AutomationTranslationResolution(text: request.sourceText, state: .failed, usedSourceFallback: true)
        )
        pendingRevision += 1
    }

    func retryAfterTransientFailure(
        _ requests: [AutomationTranslationRequest],
        reason: String? = nil,
        delay: Duration = .milliseconds(650)
    ) {
        guard !requests.isEmpty else { return }
        for request in requests {
            inFlightKeys.remove(request.key)
            requestStates[request.key] = .failed
            updateBundleState(for: request, state: .failed)
        }
        pendingRevision += 1

        Task { @MainActor in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            for request in requests {
                guard cachedTranslation(for: request) == nil else { continue }
                guard requestStates[request.key] != .unsupported else { continue }
                enqueue(request)
            }
        }
    }

    func unsupported(_ request: AutomationTranslationRequest, reason: String? = nil) {
        inFlightKeys.remove(request.key)
        requestStates[request.key] = .unsupported
        updateBundleState(for: request, state: .unsupported)
        resumeWaiters(for: request.key, text: request.sourceText)
        resumeRequiredWaiters(
            for: request.key,
            resolution: AutomationTranslationResolution(text: request.sourceText, state: .unsupported, usedSourceFallback: true)
        )
        pendingRevision += 1
    }

    func unsupportedBatch(_ requests: [AutomationTranslationRequest], reason: String? = nil) {
        guard !requests.isEmpty else { return }
        var dirtyBundlesByID: [String: AutomationTranslationBundle] = [:]
        for request in requests {
            inFlightKeys.remove(request.key)
            requestStates[request.key] = .unsupported
            if let bundle = bundleUpdatedByState(for: request, state: .unsupported, shouldPersist: true) {
                dirtyBundlesByID[bundle.id] = bundle
            }
            resumeWaiters(for: request.key, text: request.sourceText)
            resumeRequiredWaiters(
                for: request.key,
                resolution: AutomationTranslationResolution(text: request.sourceText, state: .unsupported, usedSourceFallback: true)
            )
        }
        for bundle in dirtyBundlesByID.values {
            scheduleBundleSave(bundle)
        }
        pendingRevision += 1
    }

    func translationState(for key: AutomationTranslationKey) -> AutomationTranslationState? {
        if let state = requestStates[key] {
            return state
        }
        if cachedTranslations[key] != nil {
            return .translated
        }
        return nil
    }

    func bundle(for document: AutomationTranslationDocument, language: AppLanguagePreference) -> AutomationTranslationBundle {
        loadOrCreateBundle(for: document, language: language)
    }

    private func request(for sourceText: String, language: AppLanguagePreference) -> AutomationTranslationRequest? {
        let trimmed = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let targetLanguageCode = language.translationTargetIdentifier else { return nil }
        let key = AutomationTranslationKey(sourceLanguage: "pl", targetLanguage: targetLanguageCode, sourceText: trimmed)
        return AutomationTranslationRequest(
            key: key,
            sourceText: trimmed,
            sourceLanguageCode: "pl",
            targetLanguageCode: targetLanguageCode
        )
    }

    private func externalRequest(for sourceText: String, language: AppLanguagePreference) -> AutomationTranslationRequest? {
        let trimmed = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let sourceLanguageCode = "en"
        let targetLanguageCode = language.rawValue
        guard sourceLanguageCode != targetLanguageCode else { return nil }
        let key = AutomationTranslationKey(sourceLanguage: sourceLanguageCode, targetLanguage: targetLanguageCode, sourceText: trimmed)
        return AutomationTranslationRequest(
            key: key,
            sourceText: trimmed,
            sourceLanguageCode: sourceLanguageCode,
            targetLanguageCode: targetLanguageCode
        )
    }

    private func request(
        for field: AutomationTranslationField,
        document: AutomationTranslationDocument,
        language: AppLanguagePreference
    ) -> AutomationTranslationRequest? {
        let trimmed = field.trimmedSourceText
        guard !trimmed.isEmpty else { return nil }

        let sourceLanguage = field.sourceLanguageCode ?? "auto"
        let targetLanguageCode: String
        if field.sourceLanguageCode == nil {
            targetLanguageCode = language.rawValue
        } else if sourceLanguage == "pl" {
            guard let target = language.translationTargetIdentifier else { return nil }
            targetLanguageCode = target
        } else {
            targetLanguageCode = language.rawValue
        }

        guard sourceLanguage != targetLanguageCode else { return nil }
        let key = AutomationTranslationKey(
            sourceLanguage: sourceLanguage,
            targetLanguage: targetLanguageCode,
            sourceText: trimmed
        )
        return AutomationTranslationRequest(
            key: key,
            sourceText: trimmed,
            sourceLanguageCode: field.sourceLanguageCode,
            targetLanguageCode: targetLanguageCode,
            documentID: document.id,
            fieldPath: field.path
        )
    }

    private func requiredLocalizedField(
        _ field: AutomationTranslationField,
        document: AutomationTranslationDocument,
        language: AppLanguagePreference,
        translator: Translator?
    ) async -> AutomationTranslationResolution {
        register(document, language: language)
        guard let request = request(for: field, document: document, language: language) else {
            return AutomationTranslationResolution(text: field.trimmedSourceText, state: .translated, usedSourceFallback: false)
        }
        return await requiredLocalizedText(for: request, language: language, translator: translator)
    }

    private func requiredLocalizedText(
        for request: AutomationTranslationRequest,
        language: AppLanguagePreference,
        translator: Translator?
    ) async -> AutomationTranslationResolution {
        if let cached = cachedTranslation(for: request) {
            return AutomationTranslationResolution(text: cached, state: .translated, usedSourceFallback: false)
        }
        if requestStates[request.key] == .unsupported {
            return AutomationTranslationResolution(text: request.sourceText, state: .unsupported, usedSourceFallback: true)
        }

        if let translator {
            let translated = await translator(request.sourceText, request.targetLanguageCode)
            let clean = translated.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty else {
                return AutomationTranslationResolution(text: request.sourceText, state: .failed, usedSourceFallback: true)
            }
            pendingRequests.removeAll { $0.key == request.key }
            inFlightKeys.remove(request.key)
            requestStates[request.key] = .translated
            let resolved = storeTranslatedText(clean, for: request)
            updateBundleTranslation(for: request, translatedText: resolved)
            return AutomationTranslationResolution(text: resolved, state: .translated, usedSourceFallback: false)
        }

        guard #available(iOS 18.0, *) else {
            return AutomationTranslationResolution(text: request.sourceText, state: .unsupported, usedSourceFallback: true)
        }

        return await withCheckedContinuation { continuation in
            requiredWaiters[request.key, default: []].append(continuation)
            enqueue(request)
        }
    }

    private func enqueue(_ request: AutomationTranslationRequest) {
        guard cachedTranslation(for: request) == nil else {
            requestStates[request.key] = .translated
            updateBundleState(for: request, state: .translated)
            return
        }
        guard requestStates[request.key] != .unsupported else { return }
        guard !inFlightKeys.contains(request.key) else { return }
        guard !pendingRequests.contains(where: { $0.key == request.key }) else { return }
        pendingRequests.append(request)
        pendingRequests.sort { lhs, rhs in
            let lhsPriority = translationPriority(for: lhs)
            let rhsPriority = translationPriority(for: rhs)
            if lhsPriority != rhsPriority {
                return lhsPriority < rhsPriority
            }
            return lhs.sourceText.count < rhs.sourceText.count
        }
        requestStates[request.key] = .queued
        updateBundleState(for: request, state: .queued)
        pendingRevision += 1
    }

    private func translationPriority(for request: AutomationTranslationRequest) -> Int {
        guard let path = request.fieldPath else { return 30 }
        if path == "headline"
            || path == "title"
            || path == "scopeTitle"
            || path.hasSuffix(".title")
            || path.hasSuffix(".scopeTitle")
        {
            return 0
        }
        if path == "lead"
            || path == "summary"
            || path == "presentation.lead"
            || path == "presentation.standfirst"
            || path.hasSuffix(".lead")
            || path.hasSuffix(".summary")
            || path.hasSuffix(".presentation.standfirst")
        {
            return 1
        }
        if path == "section" || path.hasSuffix(".section") || path == "status" {
            return 2
        }
        if path == "presentation.summary" || path.hasSuffix(".presentation.summary") {
            return 3
        }
        if path.contains(".presentation.bullets.") || path.contains(".signals.") || path.contains(".quickPoints.") {
            return 4
        }
        if path.contains(".tags.") || path.contains(".keywords.") {
            return 5
        }
        if path.contains(".body") || path.contains(".ttsText") || path.contains(".deeperAnalysis") {
            return 20
        }
        return 10
    }

    private func shouldEagerlyQueue(_ request: AutomationTranslationRequest, eagerPaths: Set<String>?) -> Bool {
        if let eagerPaths {
            guard let fieldPath = request.fieldPath, eagerPaths.contains(fieldPath) else { return false }
        }
        let priority = translationPriority(for: request)
        guard priority <= 5 else { return false }
        return request.sourceText.count <= 420
    }

    private func prepareForProcessing(_ request: AutomationTranslationRequest) -> AutomationTranslationRequest {
        inFlightKeys.insert(request.key)
        requestStates[request.key] = .preparing
        updateBundleState(for: request, state: .preparing)
        pendingRevision += 1
        return request
    }

    private func storeTranslatedText(
        _ translatedText: String,
        for request: AutomationTranslationRequest,
        persistBundle: Bool = true
    ) -> String {
        let clean = translatedText.trimmingCharacters(in: .whitespacesAndNewlines)
        cachedTranslations[request.key] = clean
        if persistBundle {
            updateBundleTranslation(for: request, translatedText: clean)
        }
        return clean
    }

    private func cachedTranslation(for request: AutomationTranslationRequest) -> String? {
        if let cached = cachedTranslations[request.key] {
            return cached
        }
        guard let documentID = request.documentID,
              let fieldPath = request.fieldPath,
              let document = registeredDocuments[documentID],
              let language = AppLanguagePreference(rawValue: request.targetLanguageCode)
        else { return nil }

        let bundle = loadOrCreateBundle(for: document, language: language)
        guard let translated = bundle.translations[fieldPath]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !translated.isEmpty
        else { return nil }

        cachedTranslations[request.key] = translated
        requestStates[request.key] = .translated
        return translated
    }

    private func resumeWaiters(for key: AutomationTranslationKey, text: String) {
        let continuations = waiters.removeValue(forKey: key) ?? []
        continuations.forEach { $0.resume(returning: text) }
    }

    private func resumeRequiredWaiters(for key: AutomationTranslationKey, resolution: AutomationTranslationResolution) {
        let continuations = requiredWaiters.removeValue(forKey: key) ?? []
        continuations.forEach { $0.resume(returning: resolution) }
    }

    private func loadOrCreateBundle(
        for document: AutomationTranslationDocument,
        language: AppLanguagePreference
    ) -> AutomationTranslationBundle {
        let bundleID = document.bundleID(targetLanguage: language)
        if let bundle = bundles[bundleID] {
            return bundle
        }

        if let loaded = loadBundle(id: bundleID) {
            bundles[bundleID] = loaded
            return loaded
        }

        let bundle = AutomationTranslationBundle(document: document, targetLanguage: language)
        bundles[bundleID] = bundle
        return bundle
    }

    private func updateBundleTranslation(for request: AutomationTranslationRequest, translatedText: String) {
        guard let bundle = bundleUpdatedByTranslation(for: request, translatedText: translatedText) else { return }
        scheduleBundleSave(bundle)
    }

    private func updateBundleState(for request: AutomationTranslationRequest, state: AutomationTranslationState) {
        _ = bundleUpdatedByState(
            for: request,
            state: state,
            shouldPersist: state == .translated || state == .unsupported
        )
    }

    private func bundleUpdatedByTranslation(
        for request: AutomationTranslationRequest,
        translatedText: String
    ) -> AutomationTranslationBundle? {
        guard let documentID = request.documentID,
              let fieldPath = request.fieldPath,
              let document = registeredDocuments[documentID],
              let language = AppLanguagePreference(rawValue: request.targetLanguageCode)
        else { return nil }

        var bundle = loadOrCreateBundle(for: document, language: language)
        bundle.translations[fieldPath] = translatedText
        bundle.fieldStates[fieldPath] = .translated
        bundles[bundle.id] = bundle
        return bundle
    }

    private func bundleUpdatedByState(
        for request: AutomationTranslationRequest,
        state: AutomationTranslationState,
        shouldPersist: Bool
    ) -> AutomationTranslationBundle? {
        guard let documentID = request.documentID,
              let fieldPath = request.fieldPath,
              let document = registeredDocuments[documentID],
              let language = AppLanguagePreference(rawValue: request.targetLanguageCode)
        else { return nil }

        var bundle = loadOrCreateBundle(for: document, language: language)
        switch state {
        case .translated, .unsupported:
            bundle.fieldStates[fieldPath] = state
        case .queued, .preparing, .failed:
            bundle.fieldStates.removeValue(forKey: fieldPath)
        }
        bundles[bundle.id] = bundle
        if shouldPersist {
            scheduleBundleSave(bundle)
        }
        return bundle
    }

    private func loadBundle(id: String) -> AutomationTranslationBundle? {
        let url = bundleURL(id: id)
        guard let data = try? Data(contentsOf: url) else { return nil }
        guard let decoded = try? JSONDecoder.pavbot.decode(AutomationTranslationBundle.self, from: data) else {
            return nil
        }
        let normalized = normalizedBundle(decoded)
        if normalized != decoded {
            scheduleBundleSave(normalized)
        }
        return normalized
    }

    private func normalizedBundle(_ bundle: AutomationTranslationBundle) -> AutomationTranslationBundle {
        var normalized = bundle
        normalized.fieldStates = normalized.fieldStates.compactMapValues { state in
            switch state {
            case .translated, .unsupported:
                state
            case .queued, .preparing, .failed:
                nil
            }
        }
        for (path, translation) in Array(normalized.translations) {
            let clean = translation.trimmingCharacters(in: .whitespacesAndNewlines)
            if clean.isEmpty {
                normalized.translations.removeValue(forKey: path)
                normalized.fieldStates.removeValue(forKey: path)
            } else {
                normalized.translations[path] = clean
                normalized.fieldStates[path] = .translated
            }
        }
        return normalized
    }

    private func scheduleBundleSave(_ bundle: AutomationTranslationBundle) {
        var mutableBundle = bundle
        mutableBundle.updatedAt = Date()
        bundles[mutableBundle.id] = mutableBundle
        dirtyBundleIDs.insert(mutableBundle.id)
        bundleSaveTask?.cancel()
        bundleSaveTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            self.flushPendingBundleWrites()
        }
    }

    func flushPendingBundleWrites() {
        let bundleIDs = dirtyBundleIDs
        dirtyBundleIDs.removeAll()
        bundleSaveTask?.cancel()
        bundleSaveTask = nil

        for bundleID in bundleIDs {
            guard let bundle = bundles[bundleID] else { continue }
            saveBundle(bundle)
        }
    }

    private func saveBundle(_ bundle: AutomationTranslationBundle) {
        var mutableBundle = normalizedBundle(bundle)
        mutableBundle.updatedAt = Date()
        bundles[mutableBundle.id] = mutableBundle
        do {
            try fileManager.createDirectory(at: translationsDirectory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(mutableBundle)
            try data.write(to: bundleURL(id: mutableBundle.id), options: [.atomic])
        } catch {
            // Translation bundles are a performance/consistency cache; failed writes should not block reading.
        }
    }

    private func bundleURL(id: String) -> URL {
        translationsDirectory.appendingPathComponent("\(AutomationTranslationHasher.sha256(id)).json")
    }

    private static func defaultTranslationsDirectory(fileManager: FileManager) -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return base
            .appendingPathComponent("Pavbot", isDirectory: true)
            .appendingPathComponent("Translations", isDirectory: true)
    }
}

extension AutomationTranslationDocument {
    func field(path: String) -> AutomationTranslationField? {
        fields.first { $0.path == path }
    }
}

struct AutomationTranslationFieldBuilder {
    private(set) var fields: [AutomationTranslationField] = []

    mutating func append(_ path: String, _ value: String?, sourceLanguageCode: String? = "pl") {
        guard let value else { return }
        let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        fields.append(
            AutomationTranslationField(
                path: path,
                sourceText: clean,
                sourceLanguageCode: sourceLanguageCode
            )
        )
    }

    mutating func appendList(_ path: String, _ values: [String], sourceLanguageCode: String? = "pl") {
        for (index, value) in values.enumerated() {
            append("\(path).\(index)", value, sourceLanguageCode: sourceLanguageCode)
        }
    }
}

extension MobileNewsMagazine {
    var automationTranslationDocument: AutomationTranslationDocument {
        var builder = AutomationTranslationFieldBuilder()
        builder.append("headline", headline)
        builder.append("status", status)
        builder.appendList("leadParagraphs", leadParagraphs)

        for section in sections {
            let sectionPath = "sections.\(section.id)"
            builder.append("\(sectionPath).title", section.title)
            builder.append("\(sectionPath).summary", section.summary)

            for article in section.articles {
                let articlePath = "\(sectionPath).articles.\(article.id)"
                builder.append("\(articlePath).section", article.section)
                builder.append("\(articlePath).title", article.title)
                builder.append("\(articlePath).lead", article.lead)
                builder.appendList("\(articlePath).facts", article.facts)
                builder.append("\(articlePath).analysis", article.analysis)
                builder.append("\(articlePath).whyItMatters", article.whyItMatters)
                builder.appendList("\(articlePath).tags", article.tags)
                builder.append("\(articlePath).ttsText", article.ttsText)
            }
        }

        return AutomationTranslationDocument(
            contentKind: "mobileNews",
            contentID: id,
            fields: builder.fields
        )
    }

    func translationPath(for article: MobileNewsArticle, field: String) -> String {
        let sectionID = sections.first(where: { section in
            section.articles.contains(where: { $0.id == article.id })
        })?.id ?? article.section
        return "sections.\(sectionID).articles.\(article.id).\(field)"
    }
}

extension TodayLiveTopicsSnapshot {
    var automationTranslationDocument: AutomationTranslationDocument {
        var builder = AutomationTranslationFieldBuilder()
        builder.append("headline", headline)
        builder.append("summary", summary)
        builder.append("sourceLabel", sourceLabel)

        for topic in allTopics {
            let topicPath = "topics.\(topic.id)"
            builder.append("\(topicPath).section", topic.section)
            builder.append("\(topicPath).scopeTitle", topic.scope.title)
            builder.append("\(topicPath).title", topic.title)
            builder.append("\(topicPath).lead", topic.lead)
            builder.appendList("\(topicPath).keyFacts", topic.keyFacts)
            builder.appendList("\(topicPath).reactions", topic.reactions)
            builder.append("\(topicPath).whyItMatters", topic.whyItMatters)
            builder.append("\(topicPath).context", topic.context)
            builder.appendList("\(topicPath).watchNext", topic.watchNext)
            builder.appendList("\(topicPath).tags", topic.tags)
            builder.append("\(topicPath).speechText", TodayLiveTopicSpeechController.speechText(for: topic, language: .polish))
        }

        return AutomationTranslationDocument(
            contentKind: "pulseDay",
            contentID: id,
            fields: builder.fields
        )
    }

    static func translationPath(for topic: TodayLiveTopic, field: String) -> String {
        "topics.\(topic.id).\(field)"
    }

    static func translationPathPrefix(for topic: TodayLiveTopic) -> String {
        "topics.\(topic.id)"
    }

    static func storyTranslationFieldPaths(for topic: TodayLiveTopic) -> [String: String] {
        let prefix = translationPathPrefix(for: topic)
        var paths: [String: String] = [
            "section": "\(prefix).section",
            "presentation.title": "\(prefix).title",
            "presentation.standfirst": "\(prefix).lead"
        ]
        for index in topic.keyFacts.indices {
            paths["presentation.bullets.\(index)"] = "\(prefix).keyFacts.\(index)"
        }
        for index in topic.tags.indices {
            paths["tags.\(index)"] = "\(prefix).tags.\(index)"
        }
        return paths
    }
}

extension TodayLiveTopic {
    var automationTranslationDocument: AutomationTranslationDocument {
        var builder = AutomationTranslationFieldBuilder()
        builder.append("section", section)
        builder.append("scopeTitle", scope.title)
        builder.append("title", title)
        builder.append("lead", lead)
        builder.appendList("keyFacts", keyFacts)
        builder.appendList("reactions", reactions)
        builder.append("whyItMatters", whyItMatters)
        builder.append("context", context)
        builder.appendList("watchNext", watchNext)
        builder.appendList("tags", tags)
        builder.append("speechText", TodayLiveTopicSpeechController.speechText(for: self, language: .polish))
        return AutomationTranslationDocument(
            contentKind: "pulseDayTopic",
            contentID: id,
            fields: builder.fields
        )
    }

    static func storyTranslationFieldPaths(for topic: TodayLiveTopic) -> [String: String] {
        var paths: [String: String] = [
            "section": "section",
            "presentation.title": "title",
            "presentation.standfirst": "lead"
        ]
        for index in topic.keyFacts.indices {
            paths["presentation.bullets.\(index)"] = "keyFacts.\(index)"
        }
        for index in topic.tags.indices {
            paths["tags.\(index)"] = "tags.\(index)"
        }
        return paths
    }
}

extension ResearchNewsIssue {
    var automationTranslationDocument: AutomationTranslationDocument {
        let presentation = ResearchIssuePresentation(issue: self)
        var builder = AutomationTranslationFieldBuilder()
        builder.append("status", status)
        builder.append("lead", lead)
        builder.append("presentation.eyebrow", presentation.eyebrow)
        builder.append("presentation.title", presentation.title)
        builder.append("presentation.lead", presentation.lead)
        builder.appendList("presentation.leadParagraphs", presentation.leadParagraphs)
        builder.appendList("presentation.quickPoints", presentation.quickPoints)
        builder.append("presentation.signalsTitle", presentation.signalsTitle)
        builder.append("presentation.keywordsTitle", presentation.keywordsTitle)

        for signal in presentation.signals {
            let signalPath = "presentation.signals.\(signal.id)"
            builder.append("\(signalPath).section", signal.section.rawValue)
            builder.append("\(signalPath).title", signal.title)
            builder.append("\(signalPath).summary", signal.summary)
            builder.appendList("\(signalPath).bullets", signal.bullets)
        }

        for keyword in presentation.keywords {
            builder.append("presentation.keywords.\(keyword.id).title", keyword.title)
        }

        for article in articles {
            let articlePresentation = ResearchArticlePresentation(article: article, topic: topic)
            let articlePath = "articles.\(article.id)"
            builder.append("\(articlePath).section", article.section.rawValue)
            builder.append("\(articlePath).presentation.title", articlePresentation.title)
            builder.append("\(articlePath).presentation.standfirst", articlePresentation.standfirst)
            builder.append("\(articlePath).presentation.summary", articlePresentation.summary)
            builder.appendList("\(articlePath).presentation.bullets", articlePresentation.bullets)
            builder.appendList("\(articlePath).tags", article.tags)

            builder.append("\(articlePath).title", article.title)
            builder.append("\(articlePath).summary", article.summary)
            builder.append("\(articlePath).body", article.body)
            builder.append("\(articlePath).whatHappened", article.whatHappened)
            builder.append("\(articlePath).whyItMatters", article.whyItMatters)
            builder.appendList("\(articlePath).deeperAnalysis", article.deeperAnalysis ?? [])
            builder.appendList("\(articlePath).contextPoints", article.contextPoints ?? [])
            builder.appendList("\(articlePath).presentation.paragraphs", articlePresentation.paragraphs)
            builder.appendList("\(articlePath).presentation.deeperAnalysis", articlePresentation.deeperAnalysis)
            builder.appendList("\(articlePath).presentation.contextPoints", articlePresentation.contextPoints)
            builder.append("\(articlePath).ttsText", MobileNewsArticle(researchArticle: article, topic: topic).ttsText)
        }

        return AutomationTranslationDocument(
            contentKind: "researchIssue",
            contentID: id,
            fields: builder.fields
        )
    }

    func translationPath(for article: ResearchNewsArticle, field: String) -> String {
        "articles.\(article.id).\(field)"
    }
}

extension SavedResearchArticle {
    var automationTranslationDocument: AutomationTranslationDocument {
        var builder = AutomationTranslationFieldBuilder()
        builder.append("topic.title", topic.title)
        builder.append("article.section", article.section.rawValue)
        builder.append("article.title", article.title)
        builder.append("article.summary", article.summary)
        builder.append("article.body", article.body)
        builder.append("article.whatHappened", article.whatHappened)
        builder.append("article.whyItMatters", article.whyItMatters)
        builder.appendList("article.deeperAnalysis", article.deeperAnalysis ?? [])
        builder.appendList("article.contextPoints", article.contextPoints ?? [])
        builder.appendList("article.tags", article.tags)

        return AutomationTranslationDocument(
            contentKind: "savedResearchArticle",
            contentID: id,
            fields: builder.fields
        )
    }
}

extension TodayHumorDigest {
    var automationTranslationDocument: AutomationTranslationDocument {
        var builder = AutomationTranslationFieldBuilder()
        builder.append("title", title)
        builder.append("summary", summary)
        for item in items {
            let itemPath = "items.\(item.id)"
            builder.append("\(itemPath).title", item.title)
            builder.append("\(itemPath).caption", item.caption)
            builder.append("\(itemPath).sourceName", item.sourceName)
            builder.append("\(itemPath).categoryLabel", item.categoryLabel)
            builder.append("\(itemPath).postText", item.postText)
            builder.append("\(itemPath).whyFunny", item.whyFunny)
            builder.appendList("\(itemPath).tags", item.tags)
            for highlight in item.commentHighlights ?? [] {
                let highlightPath = "\(itemPath).comments.\(highlight.id)"
                builder.append("\(highlightPath).summary", highlight.summary)
                builder.append("\(highlightPath).explanation", highlight.explanation)
                builder.append("\(highlightPath).originalBody", highlight.originalBody, sourceLanguageCode: "en")
            }
        }

        return AutomationTranslationDocument(
            contentKind: "redditRadar",
            contentID: id,
            sourceLanguage: "mixed",
            fields: builder.fields
        )
    }
}

extension SavedTodayHumorItem {
    var automationTranslationDocument: AutomationTranslationDocument {
        var builder = AutomationTranslationFieldBuilder()
        builder.append("digestTitle", digestTitle)
        let itemPath = "item.\(item.id)"
        builder.append("\(itemPath).title", item.title)
        builder.append("\(itemPath).caption", item.caption)
        builder.append("\(itemPath).sourceName", item.sourceName)
        builder.append("\(itemPath).categoryLabel", item.categoryLabel)
        builder.append("\(itemPath).postText", item.postText)
        builder.append("\(itemPath).whyFunny", item.whyFunny)
        builder.appendList("\(itemPath).tags", item.tags)
        for highlight in item.commentHighlights ?? [] {
            let highlightPath = "\(itemPath).comments.\(highlight.id)"
            builder.append("\(highlightPath).summary", highlight.summary)
            builder.append("\(highlightPath).explanation", highlight.explanation)
            builder.append("\(highlightPath).originalBody", highlight.originalBody, sourceLanguageCode: "en")
        }
        return AutomationTranslationDocument(
            contentKind: "savedRedditRadar",
            contentID: id,
            sourceLanguage: "mixed",
            fields: builder.fields
        )
    }
}

protocol SpeechAudioSessionConfiguring {
    func activateForSpeech() throws
    func deactivateAfterSpeech()
}

struct SystemSpeechAudioSession: SpeechAudioSessionConfiguring {
    func activateForSpeech() throws {
        // System AVAudioSession ownership lives in PavbotAudioSessionCoordinator.
    }

    func deactivateAfterSpeech() {
        // System AVAudioSession ownership lives in PavbotAudioSessionCoordinator.
    }
}

protocol SpeechSynthesizing: AnyObject {
    var delegate: AVSpeechSynthesizerDelegate? { get set }
    var isSpeaking: Bool { get }
    var isPaused: Bool { get }

    func speak(_ utterance: AVSpeechUtterance)
    func pauseSpeaking(at boundary: AVSpeechBoundary) -> Bool
    func continueSpeaking() -> Bool
    func stopSpeaking(at boundary: AVSpeechBoundary) -> Bool
}

extension AVSpeechSynthesizer: SpeechSynthesizing {}

enum SpeechVoiceMode: String, CaseIterable, Identifiable {
    case polishDefault
    case selectedVoice
    case personalVoice

    var id: String { rawValue }

    var title: String {
        switch self {
        case .polishDefault:
            "Polski domyślny"
        case .selectedVoice:
            "Wybrany głos"
        case .personalVoice:
            "Personal Voice"
        }
    }
}

struct SpeechVoicePreference: Equatable {
    let mode: SpeechVoiceMode
    let voiceIdentifier: String?

    static let polishDefault = SpeechVoicePreference(mode: .polishDefault, voiceIdentifier: nil)
}

enum SpeechVoiceSettings {
    static let modeDefaultsKey = "pavbot.speechVoiceMode"
    static let voiceIdentifierDefaultsKey = "pavbot.speechVoiceIdentifier"

    static func load(from defaults: UserDefaults = .standard) -> SpeechVoicePreference {
        let mode = defaults
            .string(forKey: modeDefaultsKey)
            .flatMap(SpeechVoiceMode.init(rawValue:)) ?? .polishDefault
        let identifier = defaults.string(forKey: voiceIdentifierDefaultsKey)
        return SpeechVoicePreference(mode: mode, voiceIdentifier: identifier?.isEmpty == false ? identifier : nil)
    }

    static func save(_ preference: SpeechVoicePreference, in defaults: UserDefaults = .standard) {
        defaults.set(preference.mode.rawValue, forKey: modeDefaultsKey)
        if let voiceIdentifier = preference.voiceIdentifier, !voiceIdentifier.isEmpty {
            defaults.set(voiceIdentifier, forKey: voiceIdentifierDefaultsKey)
        } else {
            defaults.removeObject(forKey: voiceIdentifierDefaultsKey)
        }
    }

    static func resolvedVoice(in defaults: UserDefaults = .standard) -> AVSpeechSynthesisVoice? {
        resolvedVoice(for: load(from: defaults), appLanguage: AppLanguagePreference.load(from: defaults))
    }

    static func resolvedVoice(
        for preference: SpeechVoicePreference,
        appLanguage: AppLanguagePreference = .polish,
        voiceWithIdentifier: (String) -> AVSpeechSynthesisVoice? = { AVSpeechSynthesisVoice(identifier: $0) },
        languageVoice: (String) -> AVSpeechSynthesisVoice? = { AVSpeechSynthesisVoice(language: $0) }
    ) -> AVSpeechSynthesisVoice? {
        let fallbackLanguage = defaultVoiceLanguage(for: appLanguage)

        switch preference.mode {
        case .polishDefault:
            return languageVoice(fallbackLanguage)
        case .selectedVoice:
            guard let identifier = preference.voiceIdentifier, let voice = voiceWithIdentifier(identifier) else {
                return languageVoice(fallbackLanguage)
            }
            return voice
        case .personalVoice:
            if let identifier = preference.voiceIdentifier, let voice = voiceWithIdentifier(identifier) {
                return voice
            }
            let personalVoiceIdentifier = SpeechVoiceCatalog.current().personalVoices.first?.id
            if let personalVoiceIdentifier, let voice = voiceWithIdentifier(personalVoiceIdentifier) {
                return voice
            }
            return languageVoice(fallbackLanguage)
        }
    }

    static func defaultVoiceLanguage(for appLanguage: AppLanguagePreference) -> String {
        switch appLanguage {
        case .polish:
            "pl-PL"
        case .english:
            "en-US"
        case .russian:
            "ru-RU"
        }
    }
}

struct SpeechVoiceOption: Identifiable, Equatable {
    let id: String
    let name: String
    let language: String
    let qualityLabel: String
    let isPersonalVoice: Bool

    var displayTitle: String {
        isPersonalVoice ? "\(name) · Personal Voice" : name
    }

    var displaySubtitle: String {
        "\(language) · \(qualityLabel)"
    }

    init(
        id: String,
        name: String,
        language: String,
        qualityLabel: String,
        isPersonalVoice: Bool
    ) {
        self.id = id
        self.name = name
        self.language = language
        self.qualityLabel = qualityLabel
        self.isPersonalVoice = isPersonalVoice
    }

    init(voice: AVSpeechSynthesisVoice) {
        id = voice.identifier
        name = voice.name
        language = voice.language
        qualityLabel = Self.qualityLabel(for: voice.quality)
        if #available(iOS 17.0, *) {
            isPersonalVoice = voice.voiceTraits.contains(.isPersonalVoice)
        } else {
            isPersonalVoice = false
        }
    }

    private static func qualityLabel(for quality: AVSpeechSynthesisVoiceQuality) -> String {
        switch quality {
        case .default:
            "Domyślny"
        case .enhanced:
            "Enhanced"
        case .premium:
            "Premium"
        @unknown default:
            "Systemowy"
        }
    }
}

enum SpeechPersonalVoiceAuthorization: String, Equatable {
    case notDetermined
    case denied
    case unsupported
    case authorized

    init(_ status: AVSpeechSynthesizer.PersonalVoiceAuthorizationStatus) {
        switch status {
        case .notDetermined:
            self = .notDetermined
        case .denied:
            self = .denied
        case .unsupported:
            self = .unsupported
        case .authorized:
            self = .authorized
        @unknown default:
            self = .unsupported
        }
    }

    var label: String {
        switch self {
        case .notDetermined:
            "Nie pytano"
        case .denied:
            "Brak zgody"
        case .unsupported:
            "Niedostępny"
        case .authorized:
            "Zgoda"
        }
    }
}

struct SpeechVoiceCatalog: Equatable {
    let voices: [SpeechVoiceOption]
    let personalVoiceAuthorization: SpeechPersonalVoiceAuthorization

    var systemVoices: [SpeechVoiceOption] {
        sortedVoices(voices.filter { !$0.isPersonalVoice })
    }

    var personalVoices: [SpeechVoiceOption] {
        guard personalVoiceAuthorization == .authorized else { return [] }
        return sortedVoices(voices.filter(\.isPersonalVoice))
    }

    var personalVoiceStatusLabel: String {
        if personalVoiceAuthorization == .authorized, personalVoices.isEmpty {
            return "Zgoda, ale brak głosu"
        }
        return personalVoiceAuthorization.label
    }

    static func current() -> SpeechVoiceCatalog {
        SpeechVoiceCatalog(
            voices: AVSpeechSynthesisVoice.speechVoices().map(SpeechVoiceOption.init(voice:)),
            personalVoiceAuthorization: SpeechPersonalVoiceAuthorization(AVSpeechSynthesizer.personalVoiceAuthorizationStatus)
        )
    }

    static func requestPersonalVoiceAuthorization() async -> SpeechPersonalVoiceAuthorization {
        await withCheckedContinuation { continuation in
            AVSpeechSynthesizer.requestPersonalVoiceAuthorization { status in
                continuation.resume(returning: SpeechPersonalVoiceAuthorization(status))
            }
        }
    }

    func selectedOption(for preference: SpeechVoicePreference) -> SpeechVoiceOption? {
        switch preference.mode {
        case .polishDefault:
            return defaultSystemVoice
        case .selectedVoice:
            if let identifier = preference.voiceIdentifier,
               let selected = systemVoices.first(where: { $0.id == identifier }) {
                return selected
            }
            return defaultSystemVoice
        case .personalVoice:
            if let identifier = preference.voiceIdentifier,
               let selected = personalVoices.first(where: { $0.id == identifier }) {
                return selected
            }
            return personalVoices.first ?? defaultSystemVoice
        }
    }

    func fallbackMessage(for preference: SpeechVoicePreference) -> String? {
        guard preference.mode != .polishDefault else { return nil }
        guard let identifier = preference.voiceIdentifier else {
            if preference.mode == .personalVoice, personalVoiceAuthorization == .authorized, personalVoices.isEmpty {
                return "Nie znaleziono Personal Voice. Utwórz głos w Ustawieniach iOS, a potem odśwież tę kartę."
            }
            return "Nie wybrano głosu. Pavbot użyje polskiego głosu domyślnego."
        }
        guard selectedOption(for: preference)?.id == identifier else {
            return "Wybrany głos nie jest dostępny na tym urządzeniu. Pavbot użyje polskiego głosu domyślnego."
        }
        return nil
    }

    func defaultSystemVoice(for languageCode: String) -> SpeechVoiceOption? {
        let languagePrefix = languageCode.split(separator: "-").first.map(String.init) ?? languageCode
        return systemVoices.first(where: { $0.language == languageCode })
            ?? systemVoices.first(where: { $0.language.hasPrefix(languagePrefix) })
            ?? systemVoices.first
    }

    var defaultSystemVoice: SpeechVoiceOption? {
        defaultSystemVoice(for: "pl-PL")
    }

    private func sortedVoices(_ options: [SpeechVoiceOption]) -> [SpeechVoiceOption] {
        options.sorted { lhs, rhs in
            let lhsPriority = languagePriority(lhs.language)
            let rhsPriority = languagePriority(rhs.language)
            if lhsPriority != rhsPriority {
                return lhsPriority < rhsPriority
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private func languagePriority(_ language: String) -> Int {
        if language == "pl-PL" { return 0 }
        if language.hasPrefix("pl") { return 1 }
        if language.hasPrefix("en") { return 2 }
        return 3
    }
}

struct SpeechSegment: Equatable, Identifiable {
    let index: Int
    let text: String
    let wordCount: Int
    let estimatedStart: Double
    let estimatedDuration: Double

    var id: Int { index }
}

struct SpeechTimeline: Equatable {
    let segments: [SpeechSegment]
    let estimatedDuration: Double

    init(text: String, wordsPerMinute: Double = 155) {
        let cleaned = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let rawSegments = cleaned
            .components(separatedBy: "\n\n")
            .map { $0.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression) }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let sourceSegments = rawSegments.isEmpty && !cleaned.isEmpty ? [cleaned] : rawSegments
        var cursor = 0.0
        var builtSegments: [SpeechSegment] = []

        for (index, segmentText) in sourceSegments.enumerated() {
            let wordCount = max(Self.wordCount(in: segmentText), 1)
            let duration = max((Double(wordCount) / max(wordsPerMinute, 1)) * 60, 2.5)
            builtSegments.append(
                SpeechSegment(
                    index: index,
                    text: segmentText,
                    wordCount: wordCount,
                    estimatedStart: cursor,
                    estimatedDuration: duration
                )
            )
            cursor += duration
        }

        segments = builtSegments
        estimatedDuration = cursor
    }

    func segmentIndex(forProgress progress: Double) -> Int {
        guard !segments.isEmpty, estimatedDuration > 0 else { return 0 }
        let clampedProgress = min(max(progress, 0), 1)
        let target = clampedProgress * estimatedDuration
        if clampedProgress >= 1 {
            return segments.indices.last ?? 0
        }
        return segments.last(where: { $0.estimatedStart <= target })?.index ?? 0
    }

    func progress(forSegmentIndex index: Int) -> Double {
        guard !segments.isEmpty, estimatedDuration > 0 else { return 0 }
        let safeIndex = min(max(index, 0), segments.count - 1)
        return min(max(segments[safeIndex].estimatedStart / estimatedDuration, 0), 1)
    }

    func segment(at index: Int) -> SpeechSegment? {
        guard !segments.isEmpty else { return nil }
        return segments[min(max(index, 0), segments.count - 1)]
    }

    private static func wordCount(in text: String) -> Int {
        text.split { !$0.isLetter && !$0.isNumber }.count
    }
}

enum SpeechPlaybackState: Equatable {
    case idle
    case playing
    case paused
    case stopping
    case failed(String)

    var isActive: Bool {
        switch self {
        case .playing, .paused, .stopping:
            return true
        case .idle, .failed:
            return false
        }
    }

    var isSpeaking: Bool {
        switch self {
        case .playing, .paused:
            return true
        case .idle, .stopping, .failed:
            return false
        }
    }

    var isPaused: Bool {
        self == .paused
    }
}

@MainActor
final class SpeechPlaybackService: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published private(set) var currentItemID: String?
    @Published private(set) var playbackState: SpeechPlaybackState = .idle
    @Published private(set) var speechRate: MobileNewsSpeechRate
    @Published private(set) var timeline: SpeechTimeline?
    @Published private(set) var currentSegmentIndex = 0
    @Published private(set) var estimatedElapsed = 0.0
    @Published private(set) var errorMessage: String?

    var isSpeaking: Bool {
        playbackState.isSpeaking
    }

    var isPaused: Bool {
        playbackState.isPaused
    }

    var estimatedDuration: Double {
        timeline?.estimatedDuration ?? 0
    }

    var currentTitleText: String? {
        currentTitle
    }

    var currentSegmentText: String? {
        timeline?.segment(at: currentSegmentIndex)?.text
    }

    private let synthesizer: SpeechSynthesizing
    private let audioSession: SpeechAudioSessionConfiguring
    private let enableSpeech: Bool
    private let rateDefaults: UserDefaults
    private let voiceProvider: () -> AVSpeechSynthesisVoice?
    private weak var audioCoordinator: PavbotAudioSessionCoordinator?
    private var audioSource: PavbotAudioActivitySource?
    private var audioTopic: String
    private var currentTitle: String?
    private var currentText: String?
    private var currentDestination: PavbotAudioDestination?
    private var currentKeyNotes: [String] = []
    private var currentTabLabel: String?
    private var segmentStartDate: Date?
    private var segmentStartElapsed = 0.0
    private var timer: Timer?
    private var playbackSessionID = UUID()
    private var currentUtterance: AVSpeechUtterance?
    private var currentUtteranceSessionID: UUID?
    private var currentSegmentWordOffset = 0

    init(
        enableSpeech: Bool = true,
        synthesizer: SpeechSynthesizing = AVSpeechSynthesizer(),
        audioSession: SpeechAudioSessionConfiguring = SystemSpeechAudioSession(),
        rateDefaults: UserDefaults = .standard,
        audioCoordinator: PavbotAudioSessionCoordinator? = nil,
        audioSource: PavbotAudioActivitySource? = nil,
        audioTopic: String = "Pavbot",
        voiceProvider: @escaping () -> AVSpeechSynthesisVoice? = { SpeechVoiceSettings.resolvedVoice() }
    ) {
        self.enableSpeech = enableSpeech
        self.synthesizer = synthesizer
        self.audioSession = audioSession
        self.rateDefaults = rateDefaults
        self.audioCoordinator = audioCoordinator
        self.audioSource = audioSource
        self.audioTopic = audioTopic
        self.voiceProvider = voiceProvider
        self.speechRate = MobileNewsSpeechRate.saved(in: rateDefaults)
        super.init()
        synthesizer.delegate = self
    }

    func configureAudioCoordinator(
        _ coordinator: PavbotAudioSessionCoordinator,
        source: PavbotAudioActivitySource,
        topic: String
    ) {
        audioCoordinator = coordinator
        audioSource = source
        audioTopic = topic
    }

    func play(
        itemID: String,
        title: String,
        text: String,
        destination: PavbotAudioDestination? = nil,
        keyNotes: [String] = [],
        tabLabel: String? = nil
    ) {
        if currentItemID == itemID, playbackState == .paused {
            resume()
            return
        }

        if currentItemID == itemID, playbackState == .playing {
            pause()
            return
        }

        start(
            itemID: itemID,
            title: title,
            text: text,
            segmentIndex: 0,
            destination: destination,
            keyNotes: keyNotes,
            tabLabel: tabLabel
        )
    }

    func failPlayback(message: String) {
        stop()
        errorMessage = message
        playbackState = .failed(message)
    }

    func start(
        itemID: String,
        title: String,
        text: String,
        segmentIndex: Int = 0,
        preservedElapsed: Double? = nil,
        wordOffset: Int = 0,
        startPaused: Bool = false,
        destination: PavbotAudioDestination? = nil,
        keyNotes: [String] = [],
        tabLabel: String? = nil
    ) {
        let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanText.isEmpty else {
            stop()
            errorMessage = "Tekst do odczytania jest pusty."
            return
        }

        do {
            try audioSession.activateForSpeech()
        } catch {
            errorMessage = PavbotUserFacingError.audio(error.localizedDescription).message
            playbackState = .failed(errorMessage ?? "Nie udało się przygotować odczytu.")
            return
        }

        let previousAudioSessionID = currentAudioSessionID
        let nextAudioSessionID = audioSessionID(itemID: itemID)
        stopSynthesizerForRestart()
        if let previousAudioSessionID, previousAudioSessionID != nextAudioSessionID {
            audioCoordinator?.deactivate(sessionID: previousAudioSessionID)
        }

        let newTimeline = SpeechTimeline(text: cleanText)
        guard !newTimeline.segments.isEmpty else {
            stop()
            errorMessage = "Tekst do odczytania nie zawiera czytelnych fragmentów."
            return
        }

        playbackSessionID = UUID()
        currentItemID = itemID
        currentTitle = title
        currentText = cleanText
        currentDestination = destination
        currentKeyNotes = keyNotes
        currentTabLabel = tabLabel
        timeline = newTimeline
        currentSegmentIndex = min(max(segmentIndex, 0), newTimeline.segments.count - 1)
        currentSegmentWordOffset = safeWordOffset(wordOffset, in: newTimeline.segment(at: currentSegmentIndex))
        let segmentStart = newTimeline.segment(at: currentSegmentIndex)?.estimatedStart ?? 0
        estimatedElapsed = min(max(preservedElapsed ?? segmentStart, 0), newTimeline.estimatedDuration)
        playbackState = startPaused ? .paused : .playing
        errorMessage = nil
        activateAudioCoordinator(isPlaying: !startPaused)
        if startPaused {
            timer?.invalidate()
            timer = nil
            segmentStartDate = nil
            segmentStartElapsed = estimatedElapsed
            return
        }
        speakCurrentSegment()
    }

    func setSpeechRate(_ rate: MobileNewsSpeechRate) {
        guard speechRate != rate else { return }
        let resumeContext = currentResumeContext()
        let wasPaused = playbackState == .paused
        speechRate = rate
        MobileNewsSpeechRate.save(rate, in: rateDefaults)

        guard isSpeaking, let currentItemID, let currentTitle, let currentText else { return }
        start(
            itemID: currentItemID,
            title: currentTitle,
            text: currentText,
            segmentIndex: resumeContext?.segmentIndex ?? currentSegmentIndex,
            preservedElapsed: resumeContext?.estimatedElapsed ?? estimatedElapsed,
            wordOffset: resumeContext?.wordOffset ?? currentSegmentWordOffset,
            startPaused: wasPaused,
            destination: currentDestination,
            keyNotes: currentKeyNotes,
            tabLabel: currentTabLabel
        )
    }

    func utteranceRate(for rate: MobileNewsSpeechRate) -> Float {
        AVSpeechUtteranceDefaultSpeechRate * rate.multiplier
    }

    func seek(toSegmentIndex index: Int) {
        guard let currentItemID, let currentTitle, let currentText, let timeline else { return }
        let safeIndex = min(max(index, 0), max(timeline.segments.count - 1, 0))
        start(
            itemID: currentItemID,
            title: currentTitle,
            text: currentText,
            segmentIndex: safeIndex,
            destination: currentDestination,
            keyNotes: currentKeyNotes,
            tabLabel: currentTabLabel
        )
    }

    func seek(to seconds: Double) {
        guard let currentItemID, let currentTitle, let currentText, let timeline else { return }
        let safeSeconds = min(max(seconds, 0), max(timeline.estimatedDuration, 0))
        let safeProgress = timeline.estimatedDuration > 0 ? safeSeconds / timeline.estimatedDuration : 0
        let segmentIndex = timeline.segmentIndex(forProgress: safeProgress)
        guard let segment = timeline.segment(at: segmentIndex) else { return }
        start(
            itemID: currentItemID,
            title: currentTitle,
            text: currentText,
            segmentIndex: segmentIndex,
            preservedElapsed: safeSeconds,
            wordOffset: wordOffset(in: segment, at: safeSeconds),
            startPaused: playbackState == .paused,
            destination: currentDestination,
            keyNotes: currentKeyNotes,
            tabLabel: currentTabLabel
        )
    }

    func skip(by seconds: Double) {
        updateEstimatedElapsed()
        seek(to: estimatedElapsed + seconds)
    }

    func seek(toProgress progress: Double) {
        guard let timeline else { return }
        seek(to: timeline.estimatedDuration * min(max(progress, 0), 1))
    }

    func pause() {
        guard playbackState == .playing else { return }
        updateEstimatedElapsed()
        if enableSpeech, !synthesizer.pauseSpeaking(at: .word) {
            errorMessage = "Nie udało się wstrzymać czytania. Spróbuj ponownie albo użyj Stop."
            playbackState = .playing
            return
        }

        playbackState = .paused
        timer?.invalidate()
        timer = nil
        updateAudioCoordinator()
    }

    func resume() {
        guard playbackState == .paused else { return }
        if currentUtterance == nil {
            playbackState = .playing
            activateAudioCoordinator(isPlaying: true)
            speakCurrentSegment()
            return
        }

        if enableSpeech, !synthesizer.continueSpeaking() {
            errorMessage = "Nie udało się wznowić czytania. Uruchom odczyt ponownie."
            playbackState = .paused
            return
        }

        playbackState = .playing
        startProgressTimer()
        activateAudioCoordinator(isPlaying: true)
    }

    func stop() {
        stop(notifyCoordinator: true)
    }

    private func stop(notifyCoordinator: Bool) {
        let sessionID = currentAudioSessionID
        playbackSessionID = UUID()
        playbackState = .stopping
        currentUtterance = nil
        if enableSpeech, synthesizer.isSpeaking || synthesizer.isPaused {
            _ = synthesizer.stopSpeaking(at: .immediate)
        }
        resetPlaybackState(finalElapsed: 0, keepError: false)
        if notifyCoordinator, let sessionID {
            audioCoordinator?.deactivate(sessionID: sessionID)
        }
        audioSession.deactivateAfterSpeech()
    }

    private func stopFromCoordinator() {
        stop(notifyCoordinator: false)
    }

    private func resetPlaybackState(finalElapsed: Double, keepError: Bool) {
        timer?.invalidate()
        timer = nil
        currentItemID = nil
        currentTitle = nil
        currentText = nil
        currentDestination = nil
        currentKeyNotes = []
        currentTabLabel = nil
        timeline = nil
        currentUtterance = nil
        currentUtteranceSessionID = nil
        currentSegmentIndex = 0
        currentSegmentWordOffset = 0
        estimatedElapsed = finalElapsed
        playbackState = .idle
        if !keepError {
            errorMessage = nil
        }
    }

    private func speakCurrentSegment() {
        guard let segment = timeline?.segment(at: currentSegmentIndex) else {
            finishPlayback()
            return
        }

        segmentStartDate = Date()
        let segmentEnd = segment.estimatedStart + segment.estimatedDuration
        let startElapsed = min(max(estimatedElapsed, segment.estimatedStart), segmentEnd)
        segmentStartElapsed = startElapsed
        estimatedElapsed = startElapsed
        startProgressTimer()

        guard enableSpeech else { return }

        let utterance = AVSpeechUtterance(string: speechText(from: segment, droppingWords: currentSegmentWordOffset))
        utterance.voice = voiceProvider() ?? AVSpeechSynthesisVoice(language: "pl-PL")
        if utterance.voice == nil {
            errorMessage = "Brak wybranego głosu TTS na urządzeniu. Sprawdź ustawienia języka, dostępności i Personal Voice w iOS."
        }
        utterance.rate = utteranceRate(for: speechRate)
        currentUtterance = utterance
        currentUtteranceSessionID = playbackSessionID
        synthesizer.speak(utterance)
    }

    private func startProgressTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateEstimatedElapsed()
            }
        }
    }

    private func updateEstimatedElapsed() {
        guard isSpeaking, !isPaused, let timeline, let segment = timeline.segment(at: currentSegmentIndex), let segmentStartDate else {
            return
        }
        let rawElapsed = segmentStartElapsed + Date().timeIntervalSince(segmentStartDate)
        estimatedElapsed = min(rawElapsed, segment.estimatedStart + segment.estimatedDuration)
        updateAudioCoordinator()
    }

    private func stopSynthesizerForRestart() {
        guard enableSpeech, synthesizer.isSpeaking || synthesizer.isPaused else { return }
        currentUtterance = nil
        currentUtteranceSessionID = nil
        _ = synthesizer.stopSpeaking(at: .immediate)
    }

    private func finishPlayback() {
        let sessionID = currentAudioSessionID
        let finalDuration = timeline?.estimatedDuration ?? estimatedElapsed
        resetPlaybackState(finalElapsed: finalDuration, keepError: true)
        if let sessionID {
            audioCoordinator?.deactivate(sessionID: sessionID, isFinished: true)
        }
        audioSession.deactivateAfterSpeech()
    }

    private var currentAudioSessionID: String? {
        guard let currentItemID else { return nil }
        return audioSessionID(itemID: currentItemID)
    }

    private func audioSessionID(itemID: String) -> String {
        "\(audioSource?.rawValue ?? "speech"):\(itemID)"
    }

    private func activateAudioCoordinator(isPlaying: Bool) {
        guard let audioCoordinator, let audioSource, let currentItemID, let currentTitle else { return }
        let session = PavbotAudioPlaybackSession(
            id: audioSessionID(itemID: currentItemID),
            source: audioSource,
            title: currentTitle,
            topic: audioTopic,
            routeID: currentItemID,
            destination: currentDestination,
            tabLabel: currentTabLabel,
            keyNotes: currentKeyNotes
        )
        audioCoordinator.activate(
            session,
            controls: PavbotAudioPlaybackControls(
                pause: { [weak self] in self?.pause() },
                resume: { [weak self] in self?.resume() },
                stop: { [weak self] in self?.stopFromCoordinator() },
                seek: { [weak self] seconds in self?.seek(to: seconds) },
                skip: { [weak self] seconds in self?.skip(by: seconds) }
            ),
            elapsed: estimatedElapsed,
            duration: estimatedDuration,
            isPlaying: isPlaying
        )
    }

    private func updateAudioCoordinator() {
        guard let currentAudioSessionID else { return }
        audioCoordinator?.update(
            sessionID: currentAudioSessionID,
            elapsed: estimatedElapsed,
            duration: estimatedDuration,
            isPlaying: playbackState == .playing
        )
    }

    private func isCurrentUtterance(_ utterance: AVSpeechUtterance) -> Bool {
        guard enableSpeech else { return false }
        guard let currentUtterance else { return false }
        guard currentUtteranceSessionID == playbackSessionID else { return false }
        return currentUtterance === utterance
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            guard self.isCurrentUtterance(utterance) else { return }
            guard self.isSpeaking, let timeline = self.timeline else { return }
            let nextIndex = self.currentSegmentIndex + 1
            if nextIndex < timeline.segments.count {
                self.currentSegmentIndex = nextIndex
                self.currentSegmentWordOffset = 0
                self.speakCurrentSegment()
            } else {
                self.finishPlayback()
            }
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            guard self.isCurrentUtterance(utterance) else { return }
            self.finishPlayback()
        }
    }
}

private struct SpeechResumeContext {
    let segmentIndex: Int
    let estimatedElapsed: Double
    let wordOffset: Int
}

private extension SpeechPlaybackService {
    func currentResumeContext() -> SpeechResumeContext? {
        updateEstimatedElapsed()
        guard let timeline, timeline.estimatedDuration > 0 else { return nil }
        let safeElapsed = min(max(estimatedElapsed, 0), timeline.estimatedDuration)
        let progress = safeElapsed / timeline.estimatedDuration
        let segmentIndex = timeline.segmentIndex(forProgress: progress)
        guard let segment = timeline.segment(at: segmentIndex) else { return nil }
        return SpeechResumeContext(
            segmentIndex: segmentIndex,
            estimatedElapsed: safeElapsed,
            wordOffset: wordOffset(in: segment, at: safeElapsed)
        )
    }

    func wordOffset(in segment: SpeechSegment, at elapsed: Double) -> Int {
        guard segment.wordCount > 1, segment.estimatedDuration > 0 else { return 0 }
        let elapsedInsideSegment = min(max(elapsed - segment.estimatedStart, 0), segment.estimatedDuration)
        let segmentProgress = min(max(elapsedInsideSegment / segment.estimatedDuration, 0), 0.95)
        return safeWordOffset(Int((Double(segment.wordCount) * segmentProgress).rounded(.down)), in: segment)
    }

    func safeWordOffset(_ wordOffset: Int, in segment: SpeechSegment?) -> Int {
        guard let segment, segment.wordCount > 1 else { return 0 }
        return min(max(wordOffset, 0), segment.wordCount - 1)
    }

    func speechText(from segment: SpeechSegment, droppingWords wordOffset: Int) -> String {
        let safeOffset = safeWordOffset(wordOffset, in: segment)
        guard safeOffset > 0 else { return segment.text }
        let words = segment.text.split(separator: " ", omittingEmptySubsequences: true)
        guard !words.isEmpty else { return segment.text }
        return words.dropFirst(min(safeOffset, max(words.count - 1, 0))).joined(separator: " ")
    }
}
