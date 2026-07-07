import SwiftUI

struct JobsBriefPresentation: Equatable {
    let title: String
    let lead: String
    let signals: [JobsBriefSignal]
    let keywords: [JobsBriefKeyword]
    let primaryRecommendation: String
    let secondaryRecommendations: [String]
    let topOpportunities: [JobOpportunity]

    init(report: JobsReport) {
        title = "Brief dnia"
        lead = Self.makeLead(from: report)
        signals = Self.makeSignals(from: report)
        keywords = Self.makeKeywords(from: report)
        primaryRecommendation = report.recommendedActions.first?.trimmedNonEmpty
            ?? "Przejrzyj top oferty i zapisz role do obserwacji."
        secondaryRecommendations = Array(report.recommendedActions.dropFirst().prefix(2)).compactMap(\.trimmedNonEmpty)
        topOpportunities = Array(report.opportunities.prefix(3))
    }

    private static func makeLead(from report: JobsReport) -> String {
        let opportunityCount = report.opportunities.count
        let changeCount = report.changes.count
        let signalCount = max(opportunityCount, changeCount)

        if signalCount == 0 {
            return "Dzisiaj rynek AI/LLM jest spokojniejszy. Najważniejsze jest utrzymanie obserwacji sprawdzonych źródeł i szybkie reagowanie, gdy pojawi się nowa rola."
        }

        let countLabel = signalCount == 1 ? "1 konkretny sygnał" : "\(min(signalCount, 3)) konkretne sygnały"
        let roleLabel = opportunityCount == 1 ? "jedną ofertą" : "\(opportunityCount) ofertami"
        return "Dzisiaj rynek AI/LLM pokazuje \(countLabel) z \(roleLabel) wartymi szybkiego przeglądu."
    }

    private static func makeSignals(from report: JobsReport) -> [JobsBriefSignal] {
        var values: [JobsBriefSignal] = report.changes.prefix(3).compactMap { change in
            guard let text = change.trimmedNonEmpty else { return nil }
            return JobsBriefSignal(
                title: "Sygnał rynku",
                body: text,
                kind: .market
            )
        }

        if values.count < 3 {
            for opportunity in report.opportunities.prefix(3 - values.count) {
                values.append(
                    JobsBriefSignal(
                        title: opportunity.company,
                        body: opportunity.previewLine,
                        kind: .opportunity
                    )
                )
            }
        }

        if values.count < 2, let risk = report.risks.first?.trimmedNonEmpty {
            values.append(JobsBriefSignal(title: "Ryzyko do sprawdzenia", body: risk, kind: .risk))
        }

        if values.count < 2, let source = report.checkedSources.first {
            values.append(
                JobsBriefSignal(
                    title: "Źródło potwierdzone",
                    body: source.title,
                    kind: .source
                )
            )
        }

        while values.count < 2 {
            let fallback = values.isEmpty
                ? JobsBriefSignal(
                    title: "Brak materialnej zmiany",
                    body: "Automatyzacja nie znalazła dziś mocnego nowego sygnału, więc warto utrzymać monitoring bez pochopnej reakcji.",
                    kind: .market
                )
                : JobsBriefSignal(
                    title: "Następny krok",
                    body: "Wróć do listy ofert i sprawdź, czy któryś profil wymaga zapisania do obserwacji.",
                    kind: .action
                )
            values.append(fallback)
        }

        return Array(values.prefix(3))
    }

    private static func makeKeywords(from report: JobsReport) -> [JobsBriefKeyword] {
        var collector = JobsBriefKeywordCollector()

        for token in ["LLM", "AI", "RAG", "Agentic", "GenAI", "ML"] {
            if report.searchCorpus.localizedCaseInsensitiveContains(token) {
                collector.add(token, kind: .technology)
            }
        }

        for opportunity in report.opportunities.prefix(3) {
            collector.add(opportunity.company, kind: .company)
            collector.add(opportunity.workMode, kind: .workMode)
            collector.add(opportunity.seniority, kind: .seniority)
            collector.add(opportunity.compensation, kind: .compensation)
            if opportunity.location.localizedCaseInsensitiveContains("wrocław")
                || opportunity.location.localizedCaseInsensitiveContains("wroclaw") {
                collector.add("Wrocław", kind: .location)
            }
            for tag in opportunity.tags.prefix(4) {
                collector.add(tag, kind: .technology)
            }
        }

        return collector.keywords
    }
}

struct JobsBriefSignal: Equatable, Identifiable {
    enum Kind: Equatable {
        case market
        case opportunity
        case risk
        case source
        case action

        var systemImage: String {
            switch self {
            case .market:
                "chart.line.uptrend.xyaxis"
            case .opportunity:
                "briefcase.fill"
            case .risk:
                "exclamationmark.triangle.fill"
            case .source:
                "checkmark.seal.fill"
            case .action:
                "arrow.right.circle.fill"
            }
        }

        var tint: Color {
            switch self {
            case .market:
                .indigo
            case .opportunity:
                .blue
            case .risk:
                .orange
            case .source:
                .green
            case .action:
                .purple
            }
        }
    }

    var id: String { "\(title)-\(body)" }

    let title: String
    let body: String
    let kind: Kind
}

struct JobsBriefKeyword: Equatable, Hashable, Identifiable {
    enum Kind: Equatable, Hashable {
        case technology
        case company
        case workMode
        case seniority
        case compensation
        case location

        var tint: Color {
            switch self {
            case .technology:
                .indigo
            case .company:
                .blue
            case .workMode:
                .cyan
            case .seniority:
                .purple
            case .compensation:
                .green
            case .location:
                .orange
            }
        }
    }

    var id: String { "\(kind)-\(title.lowercased())" }

    let title: String
    let kind: Kind
}

enum JobsKeywordHighlighter {
    static func highlightedRanges(in text: String, keywords: [JobsBriefKeyword]) -> [Range<String.Index>] {
        let terms = keywords
            .map(\.title)
            .compactMap(\.trimmedNonEmpty)
            .sorted { $0.count > $1.count }

        var ranges: [Range<String.Index>] = []
        for term in terms {
            var searchRange = text.startIndex..<text.endIndex
            while let range = text.range(
                of: term,
                options: [.caseInsensitive, .diacriticInsensitive],
                range: searchRange
            ) {
                ranges.append(range)
                searchRange = range.upperBound..<text.endIndex
            }
        }

        return ranges.sorted { $0.lowerBound < $1.lowerBound }
    }

    static func attributedText(
        _ text: String,
        keywords: [JobsBriefKeyword],
        baseFont: Font = .body,
        baseColor: Color = .primary
    ) -> AttributedString {
        var attributed = AttributedString(text)
        attributed.font = baseFont
        attributed.foregroundColor = baseColor

        for keyword in keywords.sorted(by: { $0.title.count > $1.title.count }) {
            var searchRange = text.startIndex..<text.endIndex
            while let range = text.range(
                of: keyword.title,
                options: [.caseInsensitive, .diacriticInsensitive],
                range: searchRange
            ) {
                if let attributedRange = Range(range, in: attributed) {
                    attributed[attributedRange].font = baseFont.weight(.semibold)
                    attributed[attributedRange].foregroundColor = keyword.kind.tint
                }
                searchRange = range.upperBound..<text.endIndex
            }
        }

        return attributed
    }
}

private struct JobsBriefKeywordCollector {
    private var seen: Set<String> = []
    private(set) var keywords: [JobsBriefKeyword] = []

    mutating func add(_ value: String, kind: JobsBriefKeyword.Kind) {
        guard let title = value.trimmedNonEmpty else { return }
        let key = title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        guard seen.insert(key).inserted else { return }
        keywords.append(JobsBriefKeyword(title: title, kind: kind))
    }
}

private extension JobsReport {
    var searchCorpus: String {
        let opportunityText = opportunities.map { opportunity in
            [
                opportunity.title,
                opportunity.company,
                opportunity.location,
                opportunity.workMode,
                opportunity.compensation,
                opportunity.seniority,
                opportunity.fitSummary,
                opportunity.whyInteresting,
                opportunity.tags.joined(separator: " ")
            ]
            .joined(separator: " ")
        }
        .joined(separator: " ")

        return [
            executiveSummary,
            changes.joined(separator: " "),
            risks.joined(separator: " "),
            recommendedActions.joined(separator: " "),
            opportunityText
        ]
        .joined(separator: " ")
    }
}

private extension JobOpportunity {
    var previewLine: String {
        [
            title.trimmedNonEmpty,
            workMode.trimmedNonEmpty,
            compensation.trimmedNonEmpty
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
    }
}

private extension String {
    var trimmedNonEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
