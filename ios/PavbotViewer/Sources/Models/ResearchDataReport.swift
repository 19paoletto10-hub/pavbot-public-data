import Foundation

struct ResearchDataReport: Codable, Equatable {
    let schemaVersion: Int
    let topic: String
    let runDate: String
    let runTime: String?
    let status: String
    let leadParagraphs: [String]
    let summaryBullets: [String]
    let articles: [ResearchDataArticle]
    let podcastTopics: [ResearchPodcastTopic]
    let checkedSources: [ResearchNewsSource]

    func nativeIssue(package: TopicReportPackage) throws -> ResearchNewsIssue {
        guard schemaVersion == 1 else {
            throw ResearchDataError.unsupportedSchemaVersion(schemaVersion)
        }
        guard let topicKind = ReportTopicKind(topic: topic) else {
            throw ResearchDataError.unsupportedTopic(topic)
        }

        let nativeArticles = articles.enumerated().map { index, article in
            article.nativeArticle(topic: topicKind, packageKey: package.key, index: index)
        }

        return ResearchNewsIssue(
            topic: topicKind,
            packageKey: package.key,
            date: runDate.nilIfBlank ?? package.date,
            time: runTime?.nilIfBlank ?? package.time,
            status: status.nilIfBlank ?? "Research update",
            lead: leadParagraphs
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n\n"),
            articles: nativeArticles,
            checkedSources: checkedSources,
            podcastTopics: podcastTopics,
            reportArtifact: package.researchReport,
            pdfArtifact: package.pdfReport,
            podcastBriefArtifact: package.podcastBriefPDF,
            audioArtifact: package.primaryAudio
        )
    }
}

struct ResearchDataArticle: Codable, Equatable {
    let id: String
    let section: String
    let title: String
    let standfirst: String
    let whatHappened: String
    let whyItMatters: String
    let deeperAnalysis: [String]
    let contextPoints: [String]
    let sources: [ResearchNewsSource]
    let priority: String
    let tags: [String]

    func nativeArticle(topic: ReportTopicKind, packageKey: String, index: Int) -> ResearchNewsArticle {
        let resolvedSection = ResearchNewsSection(rawValue: section)
            ?? Self.fallbackSection(for: topic, text: [title, standfirst, whatHappened, whyItMatters, tags.joined(separator: " ")].joined(separator: " "))
        let bodyParagraphs = ([whatHappened, whyItMatters] + deeperAnalysis)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let body = bodyParagraphs.joined(separator: "\n\n")

        return ResearchNewsArticle(
            id: id.nilIfBlank ?? Self.stableID(topic: topic, packageKey: packageKey, index: index, title: title),
            title: title.nilIfBlank ?? "Najważniejszy wątek",
            section: resolvedSection,
            body: body.nilIfBlank ?? standfirst,
            summary: standfirst.nilIfBlank ?? whatHappened,
            whatHappened: whatHappened.nilIfBlank,
            whyItMatters: whyItMatters.nilIfBlank,
            deeperAnalysis: deeperAnalysis.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty },
            contextPoints: contextPoints.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty },
            sources: sources,
            priority: priority.nilIfBlank,
            tags: tags
        )
    }

    private static func fallbackSection(for topic: ReportTopicKind, text: String) -> ResearchNewsSection {
        let value = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).lowercased()
        switch topic {
        case .techNews:
            if value.contains("cyber") || value.contains("security") { return .cyber }
            if value.contains("gpu") || value.contains("infrastr") || value.contains("compute") { return .infrastruktura }
            if value.contains("regul") || value.contains("law") { return .regulacje }
            if value.contains("product") || value.contains("produkt") || value.contains("app") { return .produkty }
            if value.contains("ai") || value.contains("llm") { return .ai }
            return .inne
        case .polskaSwiat:
            if value.contains("pogod") || value.contains("imgw") { return .pogoda }
            if value.contains("nato") || value.contains("bezpieczen") || value.contains("wojsk") { return .bezpieczenstwo }
            if value.contains("gospod") || value.contains("energia") { return .gospodarka }
            if value.contains("sejm") || value.contains("polity") { return .polityka }
            if value.contains("ue") || value.contains("usa") || value.contains("swiat") { return .swiat }
            if value.contains("polsk") { return .polska }
            return .inne
        case .jobs, .aktualne:
            return .inne
        }
    }

    private static func stableID(topic: ReportTopicKind, packageKey: String, index: Int, title: String) -> String {
        let slug = title
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return "\(topic.topic)-\(packageKey)-\(index)-\(slug.isEmpty ? "article" : slug)"
    }
}

enum ResearchDataError: LocalizedError, Equatable {
    case unsupportedSchemaVersion(Int)
    case unsupportedTopic(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedSchemaVersion(let version):
            "Nieobsługiwana wersja researchData: \(version)."
        case .unsupportedTopic(let topic):
            "Nieobsługiwany temat researchData: \(topic)."
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
