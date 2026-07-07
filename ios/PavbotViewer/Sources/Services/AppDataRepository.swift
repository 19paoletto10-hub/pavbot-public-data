import Foundation

protocol AppDataRepository {
    func fetchLatestPackage() async throws -> GeneratedPackage
}

protocol GeneratedPackageRemoteFetching {
    func fetchLatestGeneratedPackage() async throws -> GeneratedPackage
}

struct GitHubManifestRepository: GeneratedPackageRemoteFetching {
    enum RepositoryError: LocalizedError, Equatable {
        case invalidManifestURL(String)

        var errorDescription: String? {
            switch self {
            case .invalidManifestURL(let message):
                message
            }
        }
    }

    var client: any ManifestFetching
    var manifestURLString: @Sendable () -> String

    init(
        client: any ManifestFetching = ManifestClient(),
        manifestURLString: @escaping @Sendable () -> String
    ) {
        self.client = client
        self.manifestURLString = manifestURLString
    }

    func fetchLatestGeneratedPackage() async throws -> GeneratedPackage {
        let value = manifestURLString()
        if case .invalid(let message) = ManifestURLValidator.validate(value) {
            throw RepositoryError.invalidManifestURL(message)
        }
        guard let url = URL(string: value) else {
            throw RepositoryError.invalidManifestURL("Enter a valid manifest URL.")
        }
        let manifest = try await client.fetchManifest(from: url)
        return GeneratedPackage(manifest: manifest, manifestURL: url, source: .githubManifest)
    }
}

struct LocalGeneratedPackageCache {
    private let defaults: UserDefaults
    private let key = "pavbot.cachedGeneratedPackage"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> GeneratedPackage? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder.pavbot.decode(GeneratedPackage.self, from: data)
    }

    func save(_ package: GeneratedPackage) {
        guard let data = try? JSONEncoder().encode(package) else { return }
        defaults.set(data, forKey: key)
    }
}

struct FallbackAppDataRepository: AppDataRepository {
    enum RepositoryError: LocalizedError {
        case noDataSource

        var errorDescription: String? {
            switch self {
            case .noDataSource:
                "No Pavbot data source returned a package."
            }
        }
    }

    var cloudKit: (any GeneratedPackageRemoteFetching)?
    var gitHub: any GeneratedPackageRemoteFetching
    var cache: LocalGeneratedPackageCache

    init(
        cloudKit: (any GeneratedPackageRemoteFetching)?,
        gitHub: any GeneratedPackageRemoteFetching,
        cache: LocalGeneratedPackageCache = LocalGeneratedPackageCache()
    ) {
        self.cloudKit = cloudKit
        self.gitHub = gitHub
        self.cache = cache
    }

    func fetchLatestPackage() async throws -> GeneratedPackage {
        var lastError: Error?

        if let cloudKit {
            do {
                let package = try await cloudKit.fetchLatestGeneratedPackage()
                cache.save(package)
                return package
            } catch {
                lastError = error
            }
        }

        do {
            let package = try await gitHub.fetchLatestGeneratedPackage()
            cache.save(package)
            return package
        } catch {
            lastError = error
        }

        if let cached = cache.load() {
            return cached.withSource(.localCache)
        }

        throw lastError ?? RepositoryError.noDataSource
    }
}
