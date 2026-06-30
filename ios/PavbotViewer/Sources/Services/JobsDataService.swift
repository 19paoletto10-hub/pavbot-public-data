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
            report = cached.report
            source = cached.source
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
                cache.save(loaded.report, packageKey: loaded.package.key, source: loaded.source)
                cacheNotice = nil
                state = .loaded
                return
            } catch {
                lastError = error
                continue
            }
        }

        if report != nil {
            cacheNotice = cacheNoticeText(for: cache.load())
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
        selectedDay _: String?,
        selectedArtifactIDs: [String]
    ) -> [TopicReportPackage] {
        let sortedPackages = packages.sorted { $0.key > $1.key }
        let artifactIDs = Set(selectedArtifactIDs)
        if !artifactIDs.isEmpty,
           let package = sortedPackages.first(where: { package in
               package.artifacts.contains { artifactIDs.contains($0.id) }
           }) {
            return [package]
        }

        return sortedPackages
    }

    private func cacheNoticeText(for cached: CachedJobsReport?) -> String {
        let base = "dane Jobs"
        guard let cached else {
            return PavbotCacheNoticeCopy.refreshFailed(context: base)
        }

        let dateTime = [cached.reportDate, cached.reportTime]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let details = [dateTime, cached.source?.label ?? ""]
            .filter { !$0.isEmpty }

        guard !details.isEmpty else {
            return PavbotCacheNoticeCopy.refreshFailed(context: base)
        }
        return PavbotCacheNoticeCopy.refreshFailed(context: "\(base) (\(details.joined(separator: ", ")))")
    }
}

struct CachedJobsReport: Codable, Equatable {
    let report: JobsReport
    let packageKey: String?
    let source: JobsReportSource?
    let cachedAt: Date?

    var reportDate: String { report.runDate }
    var reportTime: String { report.runTime }

    init(
        report: JobsReport,
        packageKey: String? = nil,
        source: JobsReportSource? = nil,
        cachedAt: Date? = nil
    ) {
        self.report = report
        self.packageKey = packageKey
        self.source = source
        self.cachedAt = cachedAt
    }
}

struct JobsReportCache {
    private let defaults: UserDefaults
    private let key = "pavbot.cachedJobsReport"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> CachedJobsReport? {
        guard let data = defaults.data(forKey: key) else { return nil }
        if let cached = try? JSONDecoder.pavbot.decode(CachedJobsReport.self, from: data) {
            return cached
        }
        if let legacyReport = try? JSONDecoder.pavbot.decode(JobsReport.self, from: data) {
            return CachedJobsReport(report: legacyReport)
        }
        return nil
    }

    func save(_ report: JobsReport, packageKey: String? = nil, source: JobsReportSource? = nil) {
        let cached = CachedJobsReport(
            report: report,
            packageKey: packageKey,
            source: source,
            cachedAt: Date()
        )
        save(cached)
    }

    private func save(_ cached: CachedJobsReport) {
        guard let data = try? JSONEncoder().encode(cached) else { return }
        defaults.set(data, forKey: key)
    }
}
