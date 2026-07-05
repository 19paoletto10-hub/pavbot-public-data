import Foundation
import Observation

protocol TodayHumorFetching {
    func fetchLatestDigest(from serverURL: URL) async throws -> TodayHumorDigest
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
    private let serverURLProvider: () -> URL?
    @ObservationIgnored private let reloadGate = ReloadGate()

    init(
        client: any TodayHumorFetching = TodayHumorClient(),
        cache: TodayHumorCache = TodayHumorCache(),
        serverURLProvider: @escaping () -> URL? = { NotificationServerSettings.serverURL }
    ) {
        self.client = client
        self.cache = cache
        self.serverURLProvider = serverURLProvider
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

        let manifestArtifactURL = Self.latestRedditRadarDigestURL(
            in: manifest,
            manifestURLString: manifestURLString
        )
        var loadedDigests: [TodayHumorDigest] = []
        var lastError: Error?

        if let serverURL = serverURLProvider() {
            do {
                loadedDigests.append(try await client.fetchLatestDigest(from: serverURL))
            } catch {
                lastError = error
            }
        } else if manifestArtifactURL == nil {
            cacheNotice = nil
            state = digest == nil
                ? .failed(
                    .custom(
                        title: "Brak adresu notifiera",
                        message: "Wpisz Notification server URL w ustawieniach, aby pobrać radar memów.",
                        actionTitle: "Otwórz ustawienia",
                        systemImage: "sparkles.tv.fill",
                        tint: .purple
                    )
                )
                : .loaded
            return
        }

        if let manifestArtifactURL {
            do {
                loadedDigests.append(try await client.fetchDigest(from: manifestArtifactURL))
            } catch {
                lastError = error
            }
        }

        if let loadedDigest = Self.freshestDigest(loadedDigests) {
            digest = loadedDigest
            cache.save(loadedDigest)
            cacheNotice = nil
            state = .loaded
            return
        }

        if digest != nil {
            cacheNotice = PavbotCacheNoticeCopy.refreshFailed(context: "radar memów")
            state = .loaded
        } else if let lastError {
            cacheNotice = nil
            state = .failed(.network(lastError, context: .notifier))
        } else {
            cacheNotice = nil
            state = .failed(.network(TodayHumorClient.ClientError.invalidResponse, context: .notifier))
        }
    }

    private static func freshestDigest(_ digests: [TodayHumorDigest]) -> TodayHumorDigest? {
        digests.max { lhs, rhs in
            let lhsDate = lhs.generatedAtDate ?? Date.distantPast
            let rhsDate = rhs.generatedAtDate ?? Date.distantPast
            if lhsDate != rhsDate {
                return lhsDate < rhsDate
            }
            return lhs.id < rhs.id
        }
    }

    private static func latestRedditRadarDigestURL(
        in manifest: PavbotManifest?,
        manifestURLString: String?
    ) -> URL? {
        guard let manifest else { return nil }
        let latestArtifact = manifest.artifacts
            .filter { $0.topic == "reddit-radar" && $0.type == .redditRadarData }
            .sorted(by: PavbotArtifact.automationDisplaySort)
            .first
        return latestArtifact?.resolvedURL(manifestURL: manifestURLString.flatMap(URL.init(string:)))
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
                "Serwer humoru zwrócił nieprawidłową odpowiedź."
            case .httpStatus(let status):
                "Serwer humoru zwrócił HTTP \(status)."
            }
        }
    }

    var session: URLSession = .shared
    var decoder: JSONDecoder = .pavbot

    func fetchLatestDigest(from serverURL: URL) async throws -> TodayHumorDigest {
        try await send(Self.request(from: serverURL))
    }

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

    static func request(from serverURL: URL) throws -> URLRequest {
        let url = serverURL
            .appendingPathComponent("v1")
            .appendingPathComponent("humor")
            .appendingPathComponent("latest")
        return PavbotHTTPClient.request(for: url)
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
