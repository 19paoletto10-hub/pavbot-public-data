import Foundation
import Observation

protocol ManifestFetching {
    func fetchManifest(from url: URL) async throws -> PavbotManifest
}

enum ManifestDefaults {
    static let legacyPlaceholderManifestURL = "https://raw.githubusercontent.com/OWNER/REPO/main/public/pavbot-manifest.json"
    static let defaultManifestURL = PavbotConnectionDefaults.manifestURLString
    static let urlDefaultsKey = "pavbot.manifestURL"
}

@MainActor
@Observable
final class ManifestStore {
    typealias LoadState = PavbotLoadState

    static let defaultManifestURL = ManifestDefaults.defaultManifestURL

    var manifest: PavbotManifest?
    var lastNewArtifacts: [PavbotArtifact] = []
    var lastNewAutomations: [PavbotAutomation] = []
    var state: LoadState = .idle
    var manifestURLString: String {
        didSet {
            PavbotConnectionDefaults.enforceLegacyUserDefaults()
        }
    }
    var isUsingPlaceholderManifestURL: Bool {
        manifestURLString == ManifestDefaults.legacyPlaceholderManifestURL
    }
    var isAutoRefreshLoopRunning: Bool {
        autoRefreshTask != nil
    }
    private(set) var autoRefreshLoopStartCount = 0

    private let client: any ManifestFetching
    private let cache: ManifestCache
    private let notifier: any ArtifactNotifying
    private let liveNotificationsEnabled: () -> Bool
    @ObservationIgnored private var autoRefreshTask: Task<Void, Never>?
    @ObservationIgnored private let reloadGate = ReloadGate()

    init(
        client: any ManifestFetching = ManifestClient(),
        cache: ManifestCache = ManifestCache(),
        notifier: (any ArtifactNotifying)? = nil,
        manifestURLString: String? = nil,
        liveNotificationsEnabled: @escaping () -> Bool = { LiveNotificationSettings.isEnabled() }
    ) {
        PavbotConnectionDefaults.enforceLegacyUserDefaults()
        self.client = client
        self.cache = cache
        self.notifier = notifier ?? ArtifactNotificationService()
        self.liveNotificationsEnabled = liveNotificationsEnabled
        self.manifestURLString = manifestURLString ?? Self.defaultManifestURL
        self.manifest = cache.load()
        if self.manifest != nil {
            self.state = .loaded
        }
    }

    func load(minimumInterval: TimeInterval = 0) async {
        guard reloadGate.begin(key: "manifest", minimumInterval: minimumInterval) else { return }
        defer { reloadGate.finish(key: "manifest") }

        if isUsingPlaceholderManifestURL {
            state = manifest == nil
                ? .failed(.manifest("Set your public GitHub raw manifest URL in Settings."))
                : .loaded
            return
        }

        switch ManifestURLValidator.validate(manifestURLString) {
        case .valid:
            break
        case .invalid(let message):
            state = .failed(.manifest(message))
            return
        }

        guard let url = URL(string: manifestURLString) else {
            state = .failed(.manifest("Enter a valid manifest URL."))
            return
        }

        state = .loading
        do {
            let previousManifest = manifest
            let loadedManifest = try await client.fetchManifest(from: url)
            if let previousManifest, loadedManifest.isOlder(than: previousManifest) {
                lastNewArtifacts = []
                lastNewAutomations = []
                state = .failed(
                    .custom(
                        title: "Pokazuję dane z cache",
                        message: "Remote manifest is older than the cached manifest.",
                        actionTitle: "Odśwież ponownie",
                        systemImage: "externaldrive.fill.badge.checkmark"
                    )
                )
                return
            }
            let newArtifacts = loadedManifest.newArtifacts(comparedTo: previousManifest)
            let newAutomations = loadedManifest.newAutomations(comparedTo: previousManifest)
            lastNewArtifacts = newArtifacts
            lastNewAutomations = newAutomations
            manifest = loadedManifest
            cache.save(loadedManifest)
            if (!newArtifacts.isEmpty || !newAutomations.isEmpty) && !liveNotificationsEnabled() {
                await notifier.notify(artifacts: newArtifacts, automations: newAutomations, manifestURL: url)
            }
            state = .loaded
        } catch {
            lastNewArtifacts = []
            lastNewAutomations = []
            if manifest != nil {
                state = .failed(
                    .custom(
                        title: "Pokazuję dane z cache",
                        message: "\(PavbotCacheNoticeCopy.refreshFailed(context: "manifest")) Szczegóły: \(PavbotUserFacingError.polishMessage(from: error.localizedDescription))",
                        actionTitle: "Odśwież manifest",
                        systemImage: "externaldrive.fill.badge.checkmark"
                    )
                )
            } else {
                state = .failed(.network(error, context: .manifest))
            }
        }
    }

    func reload(minimumInterval: TimeInterval = 0) async {
        await load(minimumInterval: minimumInterval)
    }

    func startAutoRefreshLoop(intervalSeconds: UInt64 = 300) {
        guard intervalSeconds > 0, autoRefreshTask == nil else { return }
        autoRefreshLoopStartCount += 1
        autoRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: intervalSeconds * 1_000_000_000)
                guard !Task.isCancelled else { return }
                await self?.reload()
            }
        }
    }

    func stopAutoRefreshLoop() {
        autoRefreshTask?.cancel()
        autoRefreshTask = nil
    }

    deinit {
        autoRefreshTask?.cancel()
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
