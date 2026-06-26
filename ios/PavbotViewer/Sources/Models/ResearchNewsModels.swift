import Foundation
import SwiftUI

enum ResearchNewsSection: String, CaseIterable, Codable, Hashable, Identifiable {
    case ai = "AI"
    case infrastruktura = "Infrastruktura"
    case produkty = "Produkty"
    case regulacje = "Regulacje"
    case cyber = "Cyber"
    case polska = "Polska"
    case polityka = "Polityka"
    case swiat = "Świat"
    case bezpieczenstwo = "Bezpieczeństwo"
    case gospodarka = "Gospodarka"
    case pogoda = "Pogoda"
    case inne = "Inne"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .ai:
            "sparkles"
        case .infrastruktura:
            "server.rack"
        case .produkty:
            "app.badge.fill"
        case .regulacje:
            "building.columns.fill"
        case .cyber:
            "lock.shield.fill"
        case .polska:
            "flag.fill"
        case .polityka:
            "person.2.badge.gearshape.fill"
        case .swiat:
            "globe.europe.africa.fill"
        case .bezpieczenstwo:
            "shield.lefthalf.filled"
        case .gospodarka:
            "chart.line.uptrend.xyaxis"
        case .pogoda:
            "cloud.sun.fill"
        case .inne:
            "doc.text.fill"
        }
    }
}

extension ReportTopicKind {
    var newsSections: [ResearchNewsSection] {
        switch self {
        case .techNews:
            [.ai, .infrastruktura, .produkty, .regulacje, .cyber]
        case .polskaSwiat:
            [.polska, .polityka, .swiat, .bezpieczenstwo, .gospodarka, .pogoda]
        case .jobs, .aktualne:
            []
        }
    }
}

struct ResearchNewsSource: Codable, Hashable, Identifiable {
    let title: String
    let url: String

    var id: String { url.isEmpty ? title : url }
}

struct ResearchPodcastTopic: Codable, Hashable, Identifiable {
    let priority: String
    let title: String
    let rationale: String
    let sourcesLabel: String

    var id: String {
        [priority, title, rationale].joined(separator: "|")
    }
}

struct ResearchNewsArticle: Codable, Hashable, Identifiable {
    let id: String
    let title: String
    let section: ResearchNewsSection
    let body: String
    let summary: String
    var whatHappened: String? = nil
    var whyItMatters: String? = nil
    var deeperAnalysis: [String]? = nil
    var contextPoints: [String]? = nil
    let sources: [ResearchNewsSource]
    let priority: String?
    let tags: [String]

    func matchesSearch(_ query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }

        var searchable: [String] = [
            title,
            section.rawValue,
            body,
            summary,
            tags.joined(separator: " "),
            sources.map(\.title).joined(separator: " "),
            sources.map(\.url).joined(separator: " ")
        ]
        if let priority {
            searchable.append(priority)
        }

        if searchable.contains(where: {
            $0.range(of: trimmed, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }) {
            return true
        }

        let normalizedQuery = trimmed
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
        let variants = searchVariants(for: normalizedQuery)
        return searchable.contains { value in
            let normalizedValue = value
                .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                .lowercased()
            return variants.contains { normalizedValue.contains($0) }
        }
    }

    private func searchVariants(for query: String) -> [String] {
        var variants = [query]
        if query.count > 4 {
            variants.append(String(query.dropLast()))
        }
        if query.hasSuffix("a"), query.count > 4 {
            variants.append(String(query.dropLast()) + "i")
            variants.append(String(query.dropLast()) + "y")
        }
        return Array(Set(variants))
    }
}

struct ResearchNewsIssue: Codable, Hashable, Identifiable {
    let topic: ReportTopicKind
    let packageKey: String
    let date: String?
    let time: String?
    let status: String
    let lead: String
    let articles: [ResearchNewsArticle]
    let checkedSources: [ResearchNewsSource]
    let podcastTopics: [ResearchPodcastTopic]
    let reportArtifact: PavbotArtifact?
    let pdfArtifact: PavbotArtifact?
    let podcastBriefArtifact: PavbotArtifact?
    let audioArtifact: PavbotArtifact?

    var id: String { "\(topic.topic)-\(packageKey)" }

    var displayDate: String {
        [date, time]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    var sourceCount: Int {
        let articleSources = articles.flatMap(\.sources)
        return Set((checkedSources + articleSources).map(\.id)).count
    }

    var hasPDF: Bool {
        pdfArtifact != nil || podcastBriefArtifact != nil
    }

    var availableSections: [ResearchNewsSection] {
        topic.newsSections.filter { section in
            articles.contains { $0.section == section }
        }
    }

    func filteredArticles(section: ResearchNewsSection?, query: String) -> [ResearchNewsArticle] {
        articles.filter { article in
            let sectionMatches = section == nil || article.section == section
            return sectionMatches && article.matchesSearch(query)
        }
    }
}
