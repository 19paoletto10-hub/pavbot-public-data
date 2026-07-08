import Foundation
import Observation

protocol TodayHumorFetching {
    func fetchDigest(from artifactURL: URL) async throws -> TodayHumorDigest
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
    private let preferManifestArtifact: Bool
    @ObservationIgnored private let reloadGate = ReloadGate()

    init(
        client: any TodayHumorFetching = TodayHumorClient(),
        cache: TodayHumorCache = TodayHumorCache(),
        preferManifestArtifact: Bool = true
    ) {
        self.client = client
        self.cache = cache
        self.preferManifestArtifact = preferManifestArtifact
        self.digest = cache.load()
        if digest != nil {
            state = .loaded
        }
    }

    func load(
        minimumInterval: TimeInterval = 0,
        manifest: PavbotManifest? = nil,
        manifestURLString: String? = nil
    ) async {
        guard beginRequest(minimumInterval: minimumInterval) else { return }
        defer { finishRequest() }

        if digest == nil {
            state = .loading
        }

        let manifestArtifactURLs = Self.redditRadarDigestURLs(
            in: manifest,
            manifestURLString: manifestURLString
        )
        var lastError: Error?

        guard !manifestArtifactURLs.isEmpty, preferManifestArtifact else {
            cacheNotice = digest == nil ? nil : PavbotCacheNoticeCopy.refreshFailed(context: "radar memów")
            state = digest == nil
                ? .failed(
                    .custom(
                        title: "Brak radaru memów",
                        message: "CloudKit wskazuje manifest bez opublikowanego artefaktu Reddit Radar.",
                        actionTitle: "Odśwież manifest",
                        systemImage: "sparkles.tv.fill",
                        tint: .purple
                    )
                )
                : .loaded
            return
        }

        for manifestArtifactURL in manifestArtifactURLs {
            do {
                let loadedDigest = try await client.fetchDigest(from: manifestArtifactURL)
                digest = loadedDigest
                cache.save(loadedDigest)
                cacheNotice = nil
                state = .loaded
                return
            } catch {
                lastError = error
                continue
            }
        }

        if digest != nil {
            cacheNotice = PavbotCacheNoticeCopy.refreshFailed(context: "radar memów")
            state = .loaded
        } else if let lastError {
            cacheNotice = nil
            state = .failed(.network(lastError, context: .manifest))
        } else {
            cacheNotice = nil
            state = .failed(.network(TodayHumorClient.ClientError.invalidResponse, context: .manifest))
        }
    }

    private static func redditRadarDigestURLs(
        in manifest: PavbotManifest?,
        manifestURLString: String?
    ) -> [URL] {
        guard let manifest else { return [] }
        return manifest.artifacts
            .filter { $0.topic == "reddit-radar" && $0.type == .redditRadarData }
            .sorted(by: PavbotArtifact.automationDisplaySort)
            .compactMap { $0.resolvedURL(manifestURL: manifestURLString.flatMap(URL.init(string:))) }
    }

    func load(minimumInterval: TimeInterval = 0) async {
        await load(minimumInterval: minimumInterval, manifest: nil, manifestURLString: nil)
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
}

struct TodayHumorClient: TodayHumorFetching {
    enum ClientError: LocalizedError {
        case invalidResponse
        case httpStatus(Int)

        var errorDescription: String? {
            switch self {
            case .invalidResponse:
                "Artefakt Reddit Radar zwrócił nieprawidłową odpowiedź."
            case .httpStatus(let status):
                "Artefakt Reddit Radar zwrócił HTTP \(status)."
            }
        }
    }

    var session: URLSession = .shared
    var decoder: JSONDecoder = .pavbot

    func fetchDigest(from artifactURL: URL) async throws -> TodayHumorDigest {
        try await send(Self.artifactRequest(for: artifactURL))
    }

    private func send(_ request: URLRequest) async throws -> TodayHumorDigest {
        do {
            let data = try await PavbotHTTPClient(session: session).data(for: request)
            return try decoder.decode(TodayHumorDigest.self, from: data)
        } catch PavbotHTTPClientError.invalidResponse {
            throw ClientError.invalidResponse
        } catch PavbotHTTPClientError.httpStatus(let status) {
            throw ClientError.httpStatus(status)
        }
    }

    static func artifactRequest(for url: URL) -> URLRequest {
        return PavbotHTTPClient.request(for: url)
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
