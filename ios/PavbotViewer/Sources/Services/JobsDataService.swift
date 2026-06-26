import Foundation
import Observation

struct JobsReportPackage: Equatable {
    let package: TopicReportPackage
    let report: JobsReport
    let source: JobsReportSource
}

struct JobsDataClient {
    enum ClientError: LocalizedError {
        case invalidResponse
        case httpStatus(Int)

        var errorDescription: String? {
            switch self {
            case .invalidResponse:
                "Serwer danych Jobs zwrócił nieprawidłową odpowiedź."
            case .httpStatus(let status):
                "Serwer danych Jobs zwrócił HTTP \(status)."
            }
        }
    }

    var fetchData: @Sendable (URL) async throws -> Data
    var fetchText: @Sendable (URL) async throws -> String

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
        },
        fetchText: @escaping @Sendable (URL) async throws -> String = { url in
            let (data, response) = try await URLSession.shared.data(for: ManifestClient.request(for: url))
            guard let httpResponse = response as? HTTPURLResponse else {
                throw ClientError.invalidResponse
            }
            guard (200..<300).contains(httpResponse.statusCode) else {
                throw ClientError.httpStatus(httpResponse.statusCode)
            }
            return String(decoding: data, as: UTF8.self)
        }
    ) {
        self.fetchData = fetchData
        self.fetchText = fetchText
    }
}

struct JobsReportLoader {
    private let client: JobsDataClient
    private let parser: JobsMarkdownParser

    init(
        client: JobsDataClient = JobsDataClient(),
        parser: JobsMarkdownParser = JobsMarkdownParser()
    ) {
        self.client = client
        self.parser = parser
    }

    func loadReport(
        from package: TopicReportPackage,
        manifestURLString: String
    ) async throws -> JobsReportPackage {
        if let dataArtifact = package.dataArtifact,
           let dataURL = resolvedURL(for: dataArtifact, manifestURLString: manifestURLString) {
            do {
                let data = try await client.fetchData(dataURL)
                let report = try JSONDecoder.pavbot.decode(JobsReport.self, from: data)
                return JobsReportPackage(package: package, report: report, source: .jobsData)
            } catch {
                if package.researchReport == nil {
                    throw error
                }
            }
        }

        guard
            let markdownArtifact = package.researchReport,
            let markdownURL = resolvedURL(for: markdownArtifact, manifestURLString: manifestURLString)
        else {
            throw JobsMarkdownParser.ParserError.missingOpportunities
        }

        let markdown = try await client.fetchText(markdownURL)
        let report = try parser.parse(markdown)
        return JobsReportPackage(package: package, report: report, source: .markdownFallback)
    }

    private func resolvedURL(for artifact: PavbotArtifact, manifestURLString: String) -> URL? {
        artifact.resolvedURL(manifestURL: URL(string: manifestURLString))
    }
}

@MainActor
@Observable
final class JobsStore {
    typealias LoadState = PavbotLoadState

    var state: LoadState = .idle
    var report: JobsReport?
    var selectedPackage: TopicReportPackage?
    var source: JobsReportSource?
    var cacheNotice: String?

    private let loader: JobsReportLoader
    private let cache: JobsReportCache

    init(
        client: JobsDataClient = JobsDataClient(),
        cache: JobsReportCache = JobsReportCache(),
        parser: JobsMarkdownParser = JobsMarkdownParser()
    ) {
        self.loader = JobsReportLoader(client: client, parser: parser)
        self.cache = cache
        if let cached = cache.load() {
            report = cached
            state = .loaded
        }
    }

    func load(
        packages: [TopicReportPackage],
        manifestURLString: String,
        selectedDay: String?,
        selectedArtifactIDs: [String]
    ) async {
        let candidatePackages = selectPackages(from: packages, selectedDay: selectedDay, selectedArtifactIDs: selectedArtifactIDs)
        guard !candidatePackages.isEmpty else {
            cacheNotice = nil
            state = report == nil
                ? .failed(
                    .custom(
                        title: "Brak raportów Jobs",
                        message: "Brak opublikowanych raportów Jobs w manifeście.",
                        actionTitle: "Odśwież manifest",
                        systemImage: "briefcase.fill",
                        tint: .indigo
                    )
                )
                : .loaded
            return
        }

        cacheNotice = nil
        state = .loading
        var lastError: Error?
        for package in candidatePackages {
            selectedPackage = package
            do {
                let loaded = try await loader.loadReport(from: package, manifestURLString: manifestURLString)
                selectedPackage = loaded.package
                report = loaded.report
                source = loaded.source
                cache.save(loaded.report)
                cacheNotice = nil
                state = .loaded
                return
            } catch {
                lastError = error
                continue
            }
        }

        if report != nil {
            cacheNotice = "Pokazuję ostatnie zapisane dane Jobs. Odświeżenie nie powiodło się."
            state = .loaded
        } else {
            cacheNotice = nil
            state = .failed(
                lastError.map { .network($0, context: .jobs) }
                    ?? .custom(
                        title: "Nie udało się wczytać Jobs",
                        message: "Nie udało się wczytać żadnej paczki Jobs.",
                        actionTitle: "Odśwież dane",
                        systemImage: "briefcase.fill",
                        tint: .indigo
                    )
            )
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

struct JobsReportCache {
    private let defaults: UserDefaults
    private let key = "pavbot.cachedJobsReport"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> JobsReport? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder.pavbot.decode(JobsReport.self, from: data)
    }

    func save(_ report: JobsReport) {
        guard let data = try? JSONEncoder().encode(report) else { return }
        defaults.set(data, forKey: key)
    }
}
