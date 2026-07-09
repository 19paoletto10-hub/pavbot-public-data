import AVFoundation
import Combine
import Foundation
import Observation

struct MobileNewsClient {
    enum ClientError: LocalizedError {
        case invalidResponse
        case httpStatus(Int)

        var errorDescription: String? {
            switch self {
            case .invalidResponse:
                "Serwer magazynu Aktualne zwrócił nieprawidłową odpowiedź."
            case .httpStatus(let status):
                "Serwer magazynu Aktualne zwrócił HTTP \(status)."
            }
        }
    }

    var fetchData: @Sendable (URL) async throws -> Data

    init(
        fetchData: @escaping @Sendable (URL) async throws -> Data = { url in
            do {
                return try await PavbotHTTPClient().data(for: ManifestClient.request(for: url))
            } catch PavbotHTTPClientError.invalidResponse {
                throw ClientError.invalidResponse
            } catch PavbotHTTPClientError.httpStatus(let status) {
                throw ClientError.httpStatus(status)
            }
        }
    ) {
        self.fetchData = fetchData
    }
}

@MainActor
@Observable
final class MobileNewsStore {
    typealias LoadState = PavbotLoadState

    var state: LoadState = .idle
    var magazine: MobileNewsMagazine?
    var selectedPackage: TopicReportPackage?
    var cacheNotice: String?

    private let client: MobileNewsClient
    private let cache: MobileNewsCache

    init(
        client: MobileNewsClient = MobileNewsClient(),
        cache: MobileNewsCache = MobileNewsCache()
    ) {
        self.client = client
        self.cache = cache
    }

    func load(
        packages: [TopicReportPackage],
        manifestURLString: String,
        selectedDay: String?,
        selectedArtifactIDs: [String]
    ) async {
        let candidates = selectPackages(from: packages, selectedDay: selectedDay, selectedArtifactIDs: selectedArtifactIDs)
        keepOnlyMagazineMatching(candidates: candidates)
        guard !candidates.isEmpty else {
            loadCachedMagazine(matching: [])
            if magazine == nil {
                state = .failed(
                    .custom(
                        title: "Brak magazynu Aktualne",
                        message: "Manifest nie zawiera jeszcze mobileNewsData dla automatyzacji 10:15.",
                        actionTitle: "Odśwież manifest",
                        systemImage: ReportTopicKind.aktualne.systemImage,
                        tint: ReportTopicKind.aktualne.tint
                    )
                )
            }
            return
        }

        cacheNotice = nil
        state = .loading
        var lastError: Error?
        var attempts: [MobileNewsLoadAttempt] = []

        for package in candidates {
            selectedPackage = package
            guard
                let artifact = package.mobileNewsDataArtifact,
                let url = artifact.resolvedURL(manifestURL: URL(string: manifestURLString))
            else {
                attempts.append(MobileNewsLoadAttempt(package: package, artifactPath: package.mobileNewsDataArtifact?.path, url: nil))
                lastError = MobileNewsError.missingDataArtifact
                continue
            }

            attempts.append(MobileNewsLoadAttempt(package: package, artifactPath: artifact.path, url: url))
            do {
                let data = try await client.fetchData(url)
                let decoded = try JSONDecoder.pavbot.decode(MobileNewsMagazine.self, from: data)
                let magazine = decoded.withPackage(package)
                self.magazine = magazine
                selectedPackage = package
                cache.save(magazine, package: package)
                cacheNotice = nil
                state = .loaded
                return
            } catch {
                lastError = error
                continue
            }
        }

        loadCachedMagazine(matching: candidates)
        if magazine != nil {
            cacheNotice = [
                PavbotCacheNoticeCopy.refreshFailed(context: "magazyn Aktualne"),
                MobileNewsLoadAttempt.summary(for: attempts)
            ]
            .compactMap { $0 }
            .joined(separator: " ")
            state = .loaded
        } else {
            cacheNotice = nil
            state = .failed(
                .custom(
                    title: "Nie udało się wczytać Aktualne",
                    message: MobileNewsLoadAttempt.failureMessage(lastError: lastError, attempts: attempts),
                    actionTitle: "Odśwież magazyn",
                    systemImage: ReportTopicKind.aktualne.systemImage,
                    tint: ReportTopicKind.aktualne.tint
                )
            )
        }
    }

    private func keepOnlyMagazineMatching(candidates: [TopicReportPackage]) {
        guard let currentPackageID = magazine?.package?.id else { return }
        if !candidates.contains(where: { $0.id == currentPackageID }) {
            magazine = nil
        }
    }

    private func loadCachedMagazine(matching candidates: [TopicReportPackage]) {
        if let cached = cache.load(matching: candidates) {
            magazine = cached
            state = .loaded
        }
    }

    private func selectPackages(
        from packages: [TopicReportPackage],
        selectedDay: String?,
        selectedArtifactIDs: [String]
    ) -> [TopicReportPackage] {
        let loadablePackages = packages
            .filter(\.hasNativeMobileNewsContent)
            .sorted { $0.key > $1.key }
        let artifactIDs = Set(selectedArtifactIDs)
        if !artifactIDs.isEmpty,
           let package = loadablePackages.first(where: { package in
               package.artifacts.contains { artifactIDs.contains($0.id) }
           }) {
            return [package]
                + loadablePackages.filter { $0.id != package.id }
        }

        if let selectedDay = selectedDay?.trimmingCharacters(in: .whitespacesAndNewlines),
           !selectedDay.isEmpty {
            let selectedPackages = loadablePackages.filter { package in
                TopicReportPackage.keysMatch(package.key, selectedDay)
                    || package.displayDate == selectedDay
                    || package.date == selectedDay
                    || package.key.hasPrefix(selectedDay)
            }
            if !selectedPackages.isEmpty {
                return selectedPackages
                    + loadablePackages.filter { package in
                        !selectedPackages.contains(where: { $0.id == package.id })
                    }
            }
        }

        return loadablePackages
    }
}

private struct MobileNewsLoadAttempt {
    let package: TopicReportPackage
    let artifactPath: String?
    let url: URL?

    static func summary(for attempts: [Self]) -> String? {
        guard !attempts.isEmpty else { return nil }
        return "Próbowane mobileNewsData: \(attempts.map(\.displayValue).joined(separator: "; "))."
    }

    static func failureMessage(lastError: Error?, attempts: [Self]) -> String {
        let attempted = summary(for: attempts) ?? "Manifest nie wskazał żadnej paczki mobileNewsData do pobrania."
        let details = lastError.map { "Szczegóły: \($0.localizedDescription)" }
        return [
            "Nie udało się pobrać danych magazynu Aktualne.",
            attempted,
            details
        ]
        .compactMap { $0 }
        .joined(separator: " ")
    }

    private var displayValue: String {
        [
            package.key,
            artifactPath,
            url?.absoluteString
        ]
        .compactMap { value -> String? in
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed?.isEmpty == false ? trimmed : nil
        }
        .joined(separator: " -> ")
    }
}

struct MobileNewsCache {
    private let defaults: UserDefaults
    private let key = "pavbot.cachedMobileNewsMagazine.v2"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load(matching candidates: [TopicReportPackage]) -> MobileNewsMagazine? {
        guard let data = defaults.data(forKey: key) else { return nil }
        guard let cached = try? JSONDecoder.pavbot.decode(CachedMobileNewsMagazine.self, from: data) else {
            return nil
        }
        guard let package = candidates.first(where: { cached.matches(package: $0) }) else {
            return nil
        }
        return cached.magazine.withPackage(package)
    }

    func save(_ magazine: MobileNewsMagazine, package: TopicReportPackage) {
        let cached = CachedMobileNewsMagazine(
            magazine: magazine,
            packageID: package.id,
            mobileNewsDataPath: package.mobileNewsDataArtifact?.path,
            runDate: magazine.runDate,
            runTime: magazine.runTime
        )
        guard let data = try? JSONEncoder().encode(cached) else { return }
        defaults.set(data, forKey: key)
    }
}

private struct CachedMobileNewsMagazine: Codable {
    let magazine: MobileNewsMagazine
    let packageID: String
    let mobileNewsDataPath: String?
    let runDate: String
    let runTime: String?

    func matches(package: TopicReportPackage) -> Bool {
        package.id == packageID
            || package.mobileNewsDataArtifact?.path == mobileNewsDataPath
            || (package.date == runDate && package.time == runTime)
    }
}

enum MobileNewsError: LocalizedError {
    case missingDataArtifact

    var errorDescription: String? {
        switch self {
        case .missingDataArtifact:
            "Paczka Aktualne nie zawiera mobileNewsData."
        }
    }
}

enum MobileNewsSpeechRate: String, CaseIterable, Identifiable, Codable {
    case slow
    case normal
    case fast

    var id: String { rawValue }

    var label: String {
        switch self {
        case .slow:
            "0.9x"
        case .normal:
            "1x"
        case .fast:
            "1.11x"
        }
    }

    var multiplier: Float {
        switch self {
        case .slow:
            0.9
        case .normal:
            1.0
        case .fast:
            1.11
        }
    }

    private static let storageKey = "pavbot.mobileNewsSpeechRate"

    static func saved(in defaults: UserDefaults = .standard) -> MobileNewsSpeechRate {
        guard
            let rawValue = defaults.string(forKey: storageKey),
            let rate = MobileNewsSpeechRate(rawValue: rawValue)
        else {
            return .normal
        }
        return rate
    }

    static func save(_ rate: MobileNewsSpeechRate, in defaults: UserDefaults = .standard) {
        defaults.set(rate.rawValue, forKey: storageKey)
    }
}

@MainActor
final class MobileNewsSpeechController: ObservableObject {
    var currentArticleID: String? { playback.currentItemID }
    var currentTitle: String? { playback.currentTitleText }
    var hasActivePlayback: Bool { playback.currentItemID != nil || playback.isSpeaking || playback.isPaused }
    var isSpeaking: Bool { playback.isSpeaking }
    var isPaused: Bool { playback.isPaused }
    var playbackState: SpeechPlaybackState { playback.playbackState }
    var speechRate: MobileNewsSpeechRate { playback.speechRate }
    var timeline: SpeechTimeline? { playback.timeline }
    var currentSegmentIndex: Int { playback.currentSegmentIndex }
    var estimatedElapsed: Double { playback.estimatedElapsed }
    var estimatedDuration: Double { playback.estimatedDuration }
    var currentSegmentText: String? { playback.currentSegmentText }
    var errorMessage: String? { playback.errorMessage }

    private let playback: SpeechPlaybackService
    private var cancellable: AnyCancellable?

    init(
        enableSpeech: Bool = true,
        synthesizer: AVSpeechSynthesizer = AVSpeechSynthesizer(),
        audioSession: SpeechAudioSessionConfiguring = SystemSpeechAudioSession(),
        rateDefaults: UserDefaults = .standard
    ) {
        self.playback = SpeechPlaybackService(
            enableSpeech: enableSpeech,
            synthesizer: synthesizer,
            audioSession: audioSession,
            rateDefaults: rateDefaults,
            audioSource: .researchTTS,
            audioTopic: "Przegląd"
        )
        cancellable = playback.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    func configureAudioCoordinator(_ coordinator: PavbotAudioSessionCoordinator) {
        playback.configureAudioCoordinator(coordinator, source: .researchTTS, topic: "Przegląd")
    }

    func speak(_ article: MobileNewsArticle, destination: PavbotAudioDestination? = nil) {
        playback.play(
            itemID: article.id,
            title: article.title,
            text: nonBlankSpeechText(article.ttsText) ?? article.lead,
            destination: destination,
            keyNotes: Array(article.facts.prefix(3)),
            tabLabel: article.section
        )
    }

    func speak(
        _ article: MobileNewsArticle,
        language: AppLanguagePreference,
        translationStore: AutomationTranslationStore,
        destination: PavbotAudioDestination? = nil
    ) async {
        let sourceText = nonBlankSpeechText(article.speechText(language: language)) ?? article.lead
        let speechText = await translationStore.localizedText(sourceText, language: language)
        let title = await translationStore.localizedText(article.title, language: language)
        let keyNotes = await translatedKeyNotes(
            Array(article.facts.prefix(3)),
            language: language,
            translationStore: translationStore
        )
        let tabLabel = await translationStore.localizedText(article.section, language: language)

        playback.play(
            itemID: article.id,
            title: title,
            text: speechText,
            destination: destination,
            keyNotes: keyNotes,
            tabLabel: tabLabel
        )
    }

    private func translatedKeyNotes(
        _ notes: [String],
        language: AppLanguagePreference,
        translationStore: AutomationTranslationStore
    ) async -> [String] {
        var translated: [String] = []
        for note in notes {
            translated.append(await translationStore.localizedText(note, language: language))
        }
        return translated
    }

    func setSpeechRate(_ rate: MobileNewsSpeechRate) {
        playback.setSpeechRate(rate)
    }

    func utteranceRate(for rate: MobileNewsSpeechRate) -> Float {
        playback.utteranceRate(for: rate)
    }

    func seek(toSegmentIndex index: Int) {
        playback.seek(toSegmentIndex: index)
    }

    func seek(toProgress progress: Double) {
        playback.seek(toProgress: progress)
    }

    func pause() {
        playback.pause()
    }

    func resume() {
        playback.resume()
    }

    func stop() {
        playback.stop()
    }
}

private func nonBlankSpeechText(_ value: String) -> String? {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}
