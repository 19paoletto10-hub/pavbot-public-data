import Foundation
import Observation

protocol ManifestFetching {
    func fetchManifest(from url: URL) async throws -> PavbotManifest
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

    static let defaultManifestURL = "https://raw.githubusercontent.com/OWNER/REPO/main/public/pavbot-manifest.json"

    var manifest: PavbotManifest?
    var lastNewArtifacts: [PavbotArtifact] = []
    var state: LoadState = .idle
    var manifestURLString: String {
        didSet {
            UserDefaults.standard.set(manifestURLString, forKey: Self.urlDefaultsKey)
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
            ?? UserDefaults.standard.string(forKey: Self.urlDefaultsKey)
            ?? Self.defaultManifestURL
        self.manifest = cache.load()
        if self.manifest != nil {
            self.state = .loaded
        }
    }

    func load() async {
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
            let newArtifacts = loadedManifest.newArtifacts(comparedTo: previousManifest)
            lastNewArtifacts = newArtifacts
            manifest = loadedManifest
            cache.save(loadedManifest)
            if !newArtifacts.isEmpty {
                await notifier.notify(artifacts: newArtifacts, manifestURL: url)
            }
            state = .loaded
        } catch {
            lastNewArtifacts = []
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

    private static let urlDefaultsKey = "pavbot.manifestURL"
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
        let (data, response) = try await session.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClientError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw ClientError.httpStatus(httpResponse.statusCode)
        }
        return try decoder.decode(PavbotManifest.self, from: data)
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
