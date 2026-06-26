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
