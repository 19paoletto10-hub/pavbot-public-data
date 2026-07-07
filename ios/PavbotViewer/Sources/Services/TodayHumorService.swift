import Foundation
import Observation

protocol TodayHumorFetching {
    func fetchLatestDigest(from artifact: PavbotArtifact, manifestURL: URL?) async throws -> TodayHumorDigest
}

@MainActor
@Observable
final class TodayHumorStore {
    typealias LoadState = PavbotLoadState

    var digest: TodayHumorDigest?
    var state: LoadState = .idle
    var cacheNotice: String?
    var isRefreshing = false

    private let client: any TodayHumorFetching
    private let cache: TodayHumorCache
    @ObservationIgnored private let reloadGate = ReloadGate()

    init(
        client: any TodayHumorFetching = TodayHumorClient(),
        cache: TodayHumorCache = TodayHumorCache()
    ) {
        self.client = client
        self.cache = cache
        self.digest = cache.load()
        if digest != nil {
            state = .loaded
        }
    }

    func load(
        from manifest: PavbotManifest?,
        manifestURL: URL?,
        minimumInterval: TimeInterval = 0
    ) async {
        guard beginRequest(minimumInterval: minimumInterval) else { return }
        defer { finishRequest() }

        guard let artifact = Self.latestRedditRadarArtifact(in: manifest) else {
            if digest != nil {
                cacheNotice = "Pokazuję ostatni zapisany Reddit Radar. Manifest nie zawiera jeszcze świeżych danych."
                state = .loaded
            } else {
                cacheNotice = nil
                state = .failed(
                    .custom(
                        title: "Brak Reddit Radar",
                        message: "Manifest z CloudKit nie zawiera jeszcze redditRadarData dla research/reddit-radar.",
                        actionTitle: "Odśwież manifest",
                        systemImage: "sparkles.tv.fill",
                        tint: .purple
                    )
                )
            }
            return
        }

        if digest == nil {
            state = .loading
        }

        do {
            let loadedDigest = try await client.fetchLatestDigest(from: artifact, manifestURL: manifestURL)
            digest = loadedDigest
            cache.save(loadedDigest)
            cacheNotice = nil
            state = .loaded
        } catch {
            if digest != nil {
                cacheNotice = "Pokazuję ostatni zapisany radar memów. Odświeżenie nie powiodło się."
                state = .loaded
            } else {
                cacheNotice = nil
                state = .failed(.network(error, context: .notifier))
            }
        }
    }

    private func beginRequest(minimumInterval: TimeInterval = 0) -> Bool {
        guard reloadGate.begin(key: "today.humor", minimumInterval: minimumInterval) else { return false }
        isRefreshing = true
        return true
    }

    private func finishRequest() {
        reloadGate.finish(key: "today.humor")
        isRefreshing = false
    }

    private static func latestRedditRadarArtifact(in manifest: PavbotManifest?) -> PavbotArtifact? {
        manifest?.artifacts
            .filter { $0.topic == "reddit-radar" && $0.type == .redditRadarData }
            .max { lhs, rhs in
                (lhs.date ?? "", lhs.time ?? "", lhs.path) < (rhs.date ?? "", rhs.time ?? "", rhs.path)
            }
    }
}

struct TodayHumorClient: TodayHumorFetching {
    enum ClientError: LocalizedError {
        case invalidResponse
        case httpStatus(Int)
        case missingArtifactURL(String)

        var errorDescription: String? {
            switch self {
            case .invalidResponse:
                "CloudKit zwrócił nieprawidłowy artefakt Reddit Radar."
            case .httpStatus(let status):
                "Artefakt Reddit Radar zwrócił HTTP \(status)."
            case .missingArtifactURL(let path):
                "Nie można zbudować URL dla artefaktu Reddit Radar: \(path)."
            }
        }
    }

    var session: URLSession = .shared
    var decoder: JSONDecoder = .pavbot

    func fetchLatestDigest(from artifact: PavbotArtifact, manifestURL: URL?) async throws -> TodayHumorDigest {
        guard let url = artifact.resolvedURL(manifestURL: manifestURL) else {
            throw ClientError.missingArtifactURL(artifact.path)
        }
        let (data, response) = try await session.data(for: Self.request(for: url))
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClientError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw ClientError.httpStatus(httpResponse.statusCode)
        }
        return try decoder.decode(TodayHumorDigest.self, from: data)
    }

    static func request(for url: URL) -> URLRequest {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData)
        request.httpMethod = "GET"
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue("no-cache", forHTTPHeaderField: "Pragma")
        request.timeoutInterval = 12
        return request
    }
}

struct TodayHumorCache {
    private let defaults: UserDefaults
    private let key = "pavbot.cachedTodayHumorDigest"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> TodayHumorDigest? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder.pavbot.decode(TodayHumorDigest.self, from: data)
    }

    func save(_ digest: TodayHumorDigest) {
        guard let data = try? JSONEncoder().encode(digest) else { return }
        defaults.set(data, forKey: key)
    }
}
