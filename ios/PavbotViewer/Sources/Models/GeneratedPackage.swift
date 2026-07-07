import Foundation

enum GeneratedPackageEnvironment: String, Codable, Equatable {
    case dev
    case staging
    case prod

    static func inferred(from manifest: PavbotManifest) -> GeneratedPackageEnvironment {
        let base = manifest.rawBaseUrl.lowercased()
        if base.contains("staging") {
            return .staging
        }
        if base.contains("dev") || base.contains("development") {
            return .dev
        }
        return .prod
    }
}

enum GeneratedPackageSource: String, Codable, Equatable {
    case cloudKit
    case githubManifest
    case localCache
    case bundledManifest
}

struct GeneratedPackageArtifact: Codable, Equatable, Identifiable {
    let id: String
    let type: String
    let topic: String
    let title: String
    let path: String
    let url: String
    let sizeBytes: Int
    let date: String?
    let time: String?
    let storageHint: String

    init(artifact: PavbotArtifact) {
        id = artifact.id
        type = artifact.type.rawValue
        topic = artifact.topic
        title = artifact.title
        path = artifact.path
        url = artifact.url
        sizeBytes = artifact.sizeBytes
        date = artifact.date
        time = artifact.time
        storageHint = Self.storageHint(for: artifact)
    }

    private static func storageHint(for artifact: PavbotArtifact) -> String {
        switch artifact.viewerKind {
        case .audio, .pdf:
            return "cloudKitAssetOrGitHubRaw"
        case .json, .markdown:
            return "cloudKitRecordOrGitHubRaw"
        case .file:
            return "githubRaw"
        }
    }
}

struct GeneratedPackage: Codable, Equatable, Identifiable {
    static let currentSchemaVersion = "1.0.0"

    let schemaVersion: String
    let packageId: String
    let environment: GeneratedPackageEnvironment
    let generatedAt: String
    let source: GeneratedPackageSource
    let manifestURL: String?
    let manifest: PavbotManifest
    let artifacts: [GeneratedPackageArtifact]

    var id: String { packageId }
    var generatedAtDate: Date? { ISO8601DateFormatter.pavbotDate(from: generatedAt) }

    init(
        schemaVersion: String = Self.currentSchemaVersion,
        packageId: String,
        environment: GeneratedPackageEnvironment,
        generatedAt: String,
        source: GeneratedPackageSource,
        manifestURL: String?,
        manifest: PavbotManifest,
        artifacts: [GeneratedPackageArtifact]
    ) {
        self.schemaVersion = schemaVersion
        self.packageId = packageId
        self.environment = environment
        self.generatedAt = generatedAt
        self.source = source
        self.manifestURL = manifestURL
        self.manifest = manifest
        self.artifacts = artifacts
    }

    init(
        manifest: PavbotManifest,
        manifestURL: URL?,
        source: GeneratedPackageSource = .githubManifest,
        packageId: String? = nil,
        environment: GeneratedPackageEnvironment? = nil
    ) {
        self.init(
            packageId: packageId ?? Self.defaultPackageId(for: manifest),
            environment: environment ?? GeneratedPackageEnvironment.inferred(from: manifest),
            generatedAt: manifest.generatedAt,
            source: source,
            manifestURL: manifestURL?.absoluteString,
            manifest: manifest,
            artifacts: manifest.artifacts.map(GeneratedPackageArtifact.init)
        )
    }

    func withSource(_ source: GeneratedPackageSource) -> GeneratedPackage {
        GeneratedPackage(
            schemaVersion: schemaVersion,
            packageId: packageId,
            environment: environment,
            generatedAt: generatedAt,
            source: source,
            manifestURL: manifestURL,
            manifest: manifest,
            artifacts: artifacts
        )
    }

    func isOlder(than other: GeneratedPackage) -> Bool {
        guard let generatedAtDate, let otherDate = other.generatedAtDate else {
            return false
        }
        return generatedAtDate < otherDate
    }

    private static func defaultPackageId(for manifest: PavbotManifest) -> String {
        let host = URL(string: manifest.rawBaseUrl)?.host ?? "pavbot"
        let stamp = manifest.generatedAt
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: "+", with: "z")
            .replacingOccurrences(of: ".", with: "-")
        return [host, stamp]
            .joined(separator: "-")
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
            .lowercased()
    }
}
