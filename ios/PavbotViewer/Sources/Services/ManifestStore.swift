import Foundation
import Observation

protocol ManifestFetching {
    func fetchManifest(from url: URL) async throws -> PavbotManifest
}

enum ManifestDefaults {
    static let defaultManifestURL = "https://raw.githubusercontent.com/OWNER/REPO/main/public/pavbot-manifest.json"
    static let urlDefaultsKey = "pavbot.manifestURL"
}

@MainActor
@Observable
final class ManifestStore {
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    static let defaultManifestURL = ManifestDefaults.defaultManifestURL

    var manifest: PavbotManifest?
    var lastNewArtifacts: [PavbotArtifact] = []
    var lastNewAutomations: [PavbotAutomation] = []
    var state: LoadState = .idle
    var manifestURLString: String {
        didSet {
            UserDefaults.standard.set(manifestURLString, forKey: ManifestDefaults.urlDefaultsKey)
        }
    }
    var isUsingPlaceholderManifestURL: Bool {
        manifestURLString == Self.defaultManifestURL
    }

    private let client: any ManifestFetching
    private let cache: ManifestCache
    private let notifier: any ArtifactNotifying

    init(
        client: any ManifestFetching = ManifestClient(),
        cache: ManifestCache = ManifestCache(),
        notifier: (any ArtifactNotifying)? = nil,
        manifestURLString: String? = nil
    ) {
        self.client = client
        self.cache = cache
        self.notifier = notifier ?? ArtifactNotificationService()
        self.manifestURLString = manifestURLString
            ?? UserDefaults.standard.string(forKey: ManifestDefaults.urlDefaultsKey)
            ?? Self.defaultManifestURL
        self.manifest = cache.load()
        if self.manifest != nil {
            self.state = .loaded
        }
    }

    func load() async {
        guard state != .loading else { return }

        if isUsingPlaceholderManifestURL {
            state = manifest == nil
                ? .failed("Set your public GitHub raw manifest URL in Settings.")
                : .loaded
            return
        }

        switch ManifestURLValidator.validate(manifestURLString) {
        case .valid:
            break
        case .invalid(let message):
            state = .failed(message)
            return
        }

        guard let url = URL(string: manifestURLString) else {
            state = .failed("Enter a valid manifest URL.")
            return
        }

        state = .loading
        do {
            let previousManifest = manifest
            let loadedManifest = try await client.fetchManifest(from: url)
            if let previousManifest, loadedManifest.isOlder(than: previousManifest) {
                lastNewArtifacts = []
                lastNewAutomations = []
                state = .failed("Showing cached data. Remote manifest is older than the cached manifest.")
                return
            }
            let newArtifacts = loadedManifest.newArtifacts(comparedTo: previousManifest)
            let newAutomations = loadedManifest.newAutomations(comparedTo: previousManifest)
            lastNewArtifacts = newArtifacts
            lastNewAutomations = newAutomations
            manifest = loadedManifest
            cache.save(loadedManifest)
            if !newArtifacts.isEmpty || !newAutomations.isEmpty {
                await notifier.notify(artifacts: newArtifacts, automations: newAutomations, manifestURL: url)
            }
            state = .loaded
        } catch {
            lastNewArtifacts = []
            lastNewAutomations = []
            if manifest != nil {
                state = .failed("Showing cached data. Refresh failed: \(error.localizedDescription)")
            } else {
                state = .failed(error.localizedDescription)
            }
        }
    }

    func reload() async {
        await load()
    }

    func startAutoRefreshLoop(intervalSeconds: UInt64 = 300) async {
        guard intervalSeconds > 0 else { return }
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: intervalSeconds * 1_000_000_000)
            if Task.isCancelled { return }
            await reload()
        }
    }
}

struct ManifestClient: ManifestFetching {
    enum ClientError: LocalizedError {
        case invalidResponse
        case httpStatus(Int)

        var errorDescription: String? {
            switch self {
            case .invalidResponse:
                "The manifest server returned an invalid response."
            case .httpStatus(let status):
                "The manifest server returned HTTP \(status)."
            }
        }
    }

    var session: URLSession = .shared
    var decoder: JSONDecoder = .pavbot

    func fetchManifest(from url: URL) async throws -> PavbotManifest {
        let (data, response) = try await session.data(for: Self.request(for: url))
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClientError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw ClientError.httpStatus(httpResponse.statusCode)
        }
        return try decoder.decode(PavbotManifest.self, from: data)
    }

    static func request(for url: URL) -> URLRequest {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData)
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue("no-cache", forHTTPHeaderField: "Pragma")
        return request
    }
}

struct ManifestCache {
    private let defaults: UserDefaults
    private let bundle: Bundle
    private let key = "pavbot.cachedManifest"

    init(defaults: UserDefaults = .standard, bundle: Bundle = .main) {
        self.defaults = defaults
        self.bundle = bundle
    }

    func load() -> PavbotManifest? {
        if let data = defaults.data(forKey: key) {
            return try? JSONDecoder.pavbot.decode(PavbotManifest.self, from: data)
        }
        guard
            let url = bundle.url(forResource: "pavbot-manifest", withExtension: "json"),
            let data = try? Data(contentsOf: url)
        else {
            return nil
        }
        return try? JSONDecoder.pavbot.decode(PavbotManifest.self, from: data)
    }

    func save(_ manifest: PavbotManifest) {
        guard let data = try? JSONEncoder().encode(manifest) else { return }
        defaults.set(data, forKey: key)
    }
}
