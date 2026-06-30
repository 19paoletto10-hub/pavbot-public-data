import Foundation
import Observation

protocol TodayHumorFetching {
    func fetchLatestDigest(from serverURL: URL) async throws -> TodayHumorDigest
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

    func load(minimumInterval: TimeInterval = 0) async {
        guard beginRequest(minimumInterval: minimumInterval) else { return }
        defer { finishRequest() }

        guard let serverURL = serverURLProvider() else {
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

        if digest == nil {
            state = .loading
        }

        do {
            let loadedDigest = try await client.fetchLatestDigest(from: serverURL)
            digest = loadedDigest
            cache.save(loadedDigest)
            cacheNotice = nil
            state = .loaded
        } catch {
            if digest != nil {
                cacheNotice = PavbotCacheNoticeCopy.refreshFailed(context: "radar memów")
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
        let (data, response) = try await session.data(for: Self.request(from: serverURL))
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClientError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw ClientError.httpStatus(httpResponse.statusCode)
        }
        return try decoder.decode(TodayHumorDigest.self, from: data)
    }

    static func request(from serverURL: URL) throws -> URLRequest {
        let url = serverURL
            .appendingPathComponent("v1")
            .appendingPathComponent("humor")
            .appendingPathComponent("latest")
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
