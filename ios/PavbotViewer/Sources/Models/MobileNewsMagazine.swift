import Foundation

struct MobileNewsMagazine: Codable, Equatable, Identifiable {
    let schemaVersion: Int
    let topic: String
    let runDate: String
    let runTime: String?
    let status: String
    let headline: String
    let leadParagraphs: [String]
    let sections: [MobileNewsSection]
    let checkedSources: [ResearchNewsSource]
    let audioArtifacts: [MobileNewsAudioArtifact]

    var package: TopicReportPackage?

    enum CodingKeys: String, CodingKey {
        case schemaVersion
        case topic
        case runDate
        case runTime
        case status
        case headline
        case leadParagraphs
        case sections
        case checkedSources
        case audioArtifacts
    }

    var id: String {
        [mobileNewsNonBlank(topic), mobileNewsNonBlank(runDate), mobileNewsNonBlank(runTime)]
            .compactMap { $0 }
            .joined(separator: "-")
    }

    var displayDate: String {
        [mobileNewsNonBlank(runDate), mobileNewsNonBlank(runTime)]
            .compactMap { $0 }
            .joined(separator: " ")
    }

    var articleCount: Int {
        sections.reduce(0) { $0 + $1.articles.count }
    }

    var sourceCount: Int {
        let articleSources = sections.flatMap(\.articles).flatMap(\.sources)
        return Set((checkedSources + articleSources).map(\.id)).count
    }

    var pdfArtifact: PavbotArtifact? {
        package?.pdfReport
    }

    var audioArtifact: PavbotArtifact? {
        package?.primaryAudio
    }

    var podcastScriptArtifact: PavbotArtifact? {
        package?.podcastScript
    }

    func withPackage(_ package: TopicReportPackage) -> MobileNewsMagazine {
        var copy = self
        copy.package = package
        return copy
    }
}

struct MobileNewsSection: Codable, Equatable, Identifiable {
    let id: String
    let title: String
    let summary: String
    let articles: [MobileNewsArticle]

    var displaySummary: String? {
        let trimmedSummary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSummary.isEmpty else { return nil }
        let normalizedSummary = Self.normalizedText(trimmedSummary)
        let duplicatesArticleLead = articles.contains { article in
            normalizedSummary == Self.normalizedText(article.lead)
        }
        return duplicatesArticleLead ? nil : trimmedSummary
    }

    var systemImage: String {
        switch title.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).lowercased() {
        case let value where value.contains("polska"):
            "flag.fill"
        case let value where value.contains("polityka"):
            "building.columns.fill"
        case let value where value.contains("zagraniczne") || value.contains("swiat"):
            "globe.europe.africa.fill"
        case let value where value.contains("technologia"):
            "cpu.fill"
        case let value where value.contains("pogoda"):
            "cloud.sun.fill"
        default:
            "newspaper.fill"
        }
    }

    private static func normalizedText(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }
}

struct MobileNewsArticle: Codable, Equatable, Identifiable, Hashable {
    let id: String
    let section: String
    let title: String
    let lead: String
    let facts: [String]
    let analysis: String
    let whyItMatters: String
    let sources: [ResearchNewsSource]
    let tags: [String]
    let ttsText: String
    let priority: String

    func matchesSearch(_ query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        let searchable = [
            section,
            title,
            lead,
            facts.joined(separator: " "),
            analysis,
            whyItMatters,
            tags.joined(separator: " "),
            sources.map(\.title).joined(separator: " ")
        ]
        return searchable.contains {
            $0.range(of: trimmed, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }
}

extension MobileNewsArticle {
    init(researchArticle article: ResearchNewsArticle, topic: ReportTopicKind) {
        let presentation = ResearchArticlePresentation(article: article, topic: topic)
        let facts = presentation.bullets.isEmpty ? presentation.contextPoints : presentation.bullets
        let analysis = presentation.paragraphs.joined(separator: "\n\n")
        let whyItMatters = mobileNewsNonBlank(article.whyItMatters)
            ?? mobileNewsNonBlank(presentation.summary)
            ?? presentation.standfirst

        self.init(
            id: article.id,
            section: article.section.rawValue,
            title: presentation.title,
            lead: presentation.standfirst,
            facts: facts,
            analysis: analysis,
            whyItMatters: whyItMatters,
            sources: article.sources,
            tags: article.tags,
            ttsText: Self.researchSpeechText(article: article, presentation: presentation),
            priority: article.priority ?? "standard"
        )
    }

    private static func researchSpeechText(
        article: ResearchNewsArticle,
        presentation: ResearchArticlePresentation
    ) -> String {
        var sections: [String] = []
        append(article.title, to: &sections)
        appendWithTitle("Sekcja", text: article.section.rawValue, to: &sections)
        append(presentation.standfirst, to: &sections)
        appendWithTitle("Co się stało", text: article.whatHappened, to: &sections)
        appendList(title: "Najważniejsze punkty", items: presentation.bullets, to: &sections)
        appendWithTitle("Dlaczego to ważne", text: article.whyItMatters, to: &sections)
        appendList(title: "Kontekst", items: article.contextPoints ?? [], to: &sections)
        appendList(title: "Pełny opis", items: presentation.paragraphs, to: &sections)
        appendList(title: "Źródła", items: article.sources.map { "\($0.title)." }, to: &sections)
        return sections.joined(separator: "\n\n")
    }

    private static func append(_ value: String, to sections: inout [String]) {
        guard let clean = cleanResearchSpeechLine(value) else { return }
        sections.append(clean)
    }

    private static func appendWithTitle(_ title: String, text: String?, to sections: inout [String]) {
        guard let text, let clean = cleanResearchSpeechLine(text) else { return }
        sections.append("\(title). \(clean)")
    }

    private static func appendList(title: String, items: [String], to sections: inout [String]) {
        let cleanItems = items.compactMap(cleanResearchSpeechLine)
        guard !cleanItems.isEmpty else { return }
        sections.append(([title + "."] + cleanItems).joined(separator: " "))
    }

    private static func cleanResearchSpeechLine(_ value: String) -> String? {
        var result = value
        result = result.replacingOccurrences(of: #"\[([^\]]+)\]\(([^)]+)\)"#, with: "$1", options: .regularExpression)
        result = result.replacingOccurrences(of: #"https?://\S+"#, with: "", options: .regularExpression)
        result = result.replacingOccurrences(of: #"(?m)^\s*[-*]\s+"#, with: "", options: .regularExpression)
        result = result.replacingOccurrences(of: #"[*_`#>]"#, with: "", options: .regularExpression)
        result = result.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        let normalized = result.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }
}

struct MobileNewsAudioArtifact: Codable, Equatable, Hashable, Identifiable {
    let variant: String?
    let path: String?

    var id: String {
        [mobileNewsNonBlank(variant), mobileNewsNonBlank(path)]
            .compactMap { $0 }
            .joined(separator: "|")
    }
}

private func mobileNewsNonBlank(_ value: String?) -> String? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}
