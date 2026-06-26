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
            let (data, response) = try await URLSession.shared.data(for: ManifestClient.request(for: url))
            guard let httpResponse = response as? HTTPURLResponse else {
                throw ClientError.invalidResponse
            }
            guard (200..<300).contains(httpResponse.statusCode) else {
                throw ClientError.httpStatus(httpResponse.statusCode)
            }
            return data
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
        guard !candidates.isEmpty else {
            loadCachedMagazine()
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

        for package in candidates {
            selectedPackage = package
            guard
                let artifact = package.mobileNewsDataArtifact,
                let url = artifact.resolvedURL(manifestURL: URL(string: manifestURLString))
            else {
                lastError = MobileNewsError.missingDataArtifact
                continue
            }

            do {
                let data = try await client.fetchData(url)
                let decoded = try JSONDecoder.pavbot.decode(MobileNewsMagazine.self, from: data)
                let magazine = decoded.withPackage(package)
                self.magazine = magazine
                selectedPackage = package
                cache.save(magazine)
                cacheNotice = nil
                state = .loaded
                return
            } catch {
                lastError = error
                continue
            }
        }

        loadCachedMagazine()
        if magazine != nil {
            cacheNotice = "Pokazuję ostatni zapisany magazyn Aktualne. Odświeżenie nie powiodło się."
            state = .loaded
        } else {
            cacheNotice = nil
            state = .failed(
                lastError.map { .network($0, context: .preview) }
                    ?? .custom(
                        title: "Nie udało się wczytać Aktualne",
                        message: "Nie udało się pobrać danych magazynu 10:15.",
                        actionTitle: "Odśwież magazyn",
                        systemImage: ReportTopicKind.aktualne.systemImage,
                        tint: ReportTopicKind.aktualne.tint
                    )
            )
        }
    }

    private func loadCachedMagazine() {
        if let cached = cache.load() {
            magazine = cached
            state = .loaded
        }
    }

    private func selectPackages(
        from packages: [TopicReportPackage],
        selectedDay: String?,
        selectedArtifactIDs: [String]
    ) -> [TopicReportPackage] {
        let artifactIDs = Set(selectedArtifactIDs)
        if !artifactIDs.isEmpty,
           let package = packages.first(where: { package in
               package.artifacts.contains { artifactIDs.contains($0.id) }
           }) {
            return [package]
        }

        if let selectedDay,
           let package = packages.first(where: { $0.date == selectedDay || $0.key.hasPrefix(selectedDay) }) {
            return [package]
        }

        return packages
    }
}

struct MobileNewsCache {
    private let defaults: UserDefaults
    private let key = "pavbot.cachedMobileNewsMagazine"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> MobileNewsMagazine? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder.pavbot.decode(MobileNewsMagazine.self, from: data)
    }

    func save(_ magazine: MobileNewsMagazine) {
        guard let data = try? JSONEncoder().encode(magazine) else { return }
        defaults.set(data, forKey: key)
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
            rateDefaults: rateDefaults
        )
        cancellable = playback.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    func speak(_ article: MobileNewsArticle) {
        playback.play(
            itemID: article.id,
            title: article.title,
            text: nonBlankSpeechText(article.ttsText) ?? article.lead
        )
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
