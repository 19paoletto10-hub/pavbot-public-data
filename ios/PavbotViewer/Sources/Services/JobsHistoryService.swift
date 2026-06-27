import Foundation
import Observation

struct JobsHistorySnapshot: Equatable {
    let anchorDate: String
    let includedDates: [String]
    let reportCount: Int
    let failedPackageCount: Int
    let sourceBreakdown: [JobsReportSource: Int]
    let opportunities: [HistoricalJobOpportunity]

    var dateBuckets: [JobsDateBucket] {
        [JobsDateBucket.all] + includedDates.enumerated().map { index, date in
            JobsDateBucket(date: date, title: JobsDateBucket.title(forOffset: index))
        }
    }

    var dateRangeLabel: String {
        guard let newest = includedDates.first, let oldest = includedDates.last else {
            return "Brak dat"
        }
        if newest == oldest {
            return newest
        }
        return "\(oldest) - \(newest)"
    }

    func validatedSelectedDate(_ date: String?) -> String? {
        guard let date, includedDates.contains(date) else {
            return nil
        }
        return date
    }

    func filteredOpportunities(
        filter: JobsFilter,
        date: String?,
        searchText: String
    ) -> [HistoricalJobOpportunity] {
        let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return opportunities
            .filter { item in
                guard let date else { return true }
                return item.reportDates.contains(date)
            }
            .filter { filter.matches($0.opportunity) }
            .filter { item in
                guard !trimmedSearch.isEmpty else { return true }
                return item.normalizedSearchText.range(
                    of: trimmedSearch,
                    options: [.caseInsensitive, .diacriticInsensitive]
                ) != nil
            }
    }
}

struct JobsDateBucket: Identifiable, Hashable {
    let date: String?
    let title: String

    var id: String { date ?? "all" }

    static let all = JobsDateBucket(date: nil, title: "Wszystkie")

    static func title(forOffset offset: Int) -> String {
        switch offset {
        case 0:
            "Dzisiaj"
        case 1:
            "Wczoraj"
        case 2:
            "2 dni temu"
        default:
            "\(offset) dni temu"
        }
    }
}

struct HistoricalJobOpportunity: Identifiable, Equatable, Hashable {
    let id: String
    let opportunity: JobOpportunity
    let firstSeen: String
    let latestSeen: String
    let reportDates: [String]
    let occurrenceCount: Int
    let sourceURLs: [String]

    var normalizedSearchText: String {
        ([
            opportunity.normalizedSearchText,
            opportunity.company,
            opportunity.title,
            firstSeen,
            latestSeen
        ] + reportDates + sourceURLs)
            .joined(separator: " ")
    }
}

@MainActor
@Observable
final class JobsHistoryStore {
    typealias LoadState = PavbotLoadState

    var state: LoadState = .idle
    var snapshot: JobsHistorySnapshot?

    private let loader: JobsReportLoader

    init(
        client: JobsDataClient = JobsDataClient(),
        parser: JobsMarkdownParser = JobsMarkdownParser()
    ) {
        self.loader = JobsReportLoader(client: client, parser: parser)
    }

    func load(
        packages: [TopicReportPackage],
        manifestURLString: String,
        selectedDay: String?
    ) async {
        guard let window = Self.historyWindow(from: packages, selectedDay: selectedDay) else {
            state = .failed(
                .custom(
                    title: "Brak historii Jobs",
                    message: "Brak raportów Jobs z ostatnich dni.",
                    actionTitle: "Odśwież Jobs",
                    systemImage: "clock.badge.questionmark",
                    tint: .indigo
                )
            )
            return
        }

        state = .loading
        var loadedReports: [JobsReportPackage] = []
        var failedPackageCount = 0
        var sourceBreakdown: [JobsReportSource: Int] = [:]

        for package in window.packages {
            do {
                let loaded = try await loader.loadReport(from: package, manifestURLString: manifestURLString)
                loadedReports.append(loaded)
                sourceBreakdown[loaded.source, default: 0] += 1
            } catch {
                failedPackageCount += 1
            }
        }

        guard !loadedReports.isEmpty else {
            snapshot = nil
            state = .failed(
                .custom(
                    title: "Nie udało się wczytać historii Jobs",
                    message: "Nie udało się wczytać żadnej historycznej paczki Jobs.",
                    actionTitle: "Odśwież historię",
                    systemImage: "clock.arrow.circlepath",
                    tint: .indigo
                )
            )
            return
        }

        snapshot = JobsHistorySnapshot(
            anchorDate: window.anchorDate,
            includedDates: window.includedDates,
            reportCount: loadedReports.count,
            failedPackageCount: failedPackageCount,
            sourceBreakdown: sourceBreakdown,
            opportunities: Self.mergeOpportunities(from: loadedReports)
        )
        state = .loaded
    }

    private static func historyWindow(
        from packages: [TopicReportPackage],
        selectedDay: String?
    ) -> (anchorDate: String, includedDates: [String], packages: [TopicReportPackage])? {
        let sortedPackages = packages.sorted { $0.key > $1.key }
        let anchorDateString = selectedDay.flatMap { day -> String? in
            DateFormatter.pavbotDay.date(from: day) == nil ? nil : day
        }
            ?? sortedPackages.compactMap(\.date).sorted(by: >).first
        guard
            let anchorDateString,
            let anchorDate = DateFormatter.pavbotDay.date(from: anchorDateString)
        else {
            return nil
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        let includedDates = (0...2).compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: anchorDate)?.pavbotDayString
        }
        let includedDateSet = Set(includedDates)
        let windowPackages = sortedPackages.filter { package in
            guard let date = package.date else { return false }
            return includedDateSet.contains(date)
        }

        return (anchorDateString, includedDates, windowPackages)
    }

    private static func mergeOpportunities(from reports: [JobsReportPackage]) -> [HistoricalJobOpportunity] {
        var accumulators: [String: HistoricalOpportunityAccumulator] = [:]

        for reportPackage in reports {
            let reportDate = reportPackage.report.runDate
            for opportunity in reportPackage.report.opportunities {
                let key = HistoricalOpportunityAccumulator.key(for: opportunity)
                accumulators[key, default: HistoricalOpportunityAccumulator(id: key)]
                    .add(opportunity: opportunity, reportDate: reportDate)
            }
        }

        return accumulators.values
            .map(\.historicalOpportunity)
            .sorted { lhs, rhs in
                if lhs.latestSeen != rhs.latestSeen {
                    return lhs.latestSeen > rhs.latestSeen
                }
                if lhs.opportunity.rank != rhs.opportunity.rank {
                    return lhs.opportunity.rank < rhs.opportunity.rank
                }
                return lhs.opportunity.company.localizedCaseInsensitiveCompare(rhs.opportunity.company) == .orderedAscending
            }
    }
}

private struct HistoricalOpportunityAccumulator {
    let id: String
    private(set) var latestOpportunity: JobOpportunity?
    private(set) var firstSeen: String?
    private(set) var latestSeen: String?
    private(set) var reportDates: [String] = []
    private(set) var occurrenceCount = 0
    private(set) var sourceURLs: [String] = []

    mutating func add(opportunity: JobOpportunity, reportDate: String) {
        occurrenceCount += 1

        if latestSeen == nil || reportDate > (latestSeen ?? "") {
            latestSeen = reportDate
            latestOpportunity = opportunity
        }
        if firstSeen == nil || reportDate < (firstSeen ?? "") {
            firstSeen = reportDate
        }
        if !reportDates.contains(reportDate) {
            reportDates.append(reportDate)
            reportDates.sort(by: >)
        }
        for sourceURL in opportunity.sourceURLs where !sourceURLs.contains(sourceURL) {
            sourceURLs.append(sourceURL)
        }
    }

    var historicalOpportunity: HistoricalJobOpportunity {
        HistoricalJobOpportunity(
            id: id,
            opportunity: latestOpportunity ?? JobOpportunity(
                rank: 0,
                title: "Nieznana rola",
                company: "Nieznana firma",
                location: "",
                workMode: "",
                compensation: "",
                seniority: "",
                fitSummary: "",
                whyInteresting: "",
                uncertainty: "",
                sourceURLs: [],
                tags: []
            ),
            firstSeen: firstSeen ?? "",
            latestSeen: latestSeen ?? "",
            reportDates: reportDates,
            occurrenceCount: occurrenceCount,
            sourceURLs: sourceURLs
        )
    }

    static func key(for opportunity: JobOpportunity) -> String {
        [
            opportunity.company,
            opportunity.title,
            opportunity.sourceURLs.first ?? ""
        ]
        .map(normalizedKeyPart)
        .joined(separator: "|")
    }

    private static func normalizedKeyPart(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "pl_PL"))
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
