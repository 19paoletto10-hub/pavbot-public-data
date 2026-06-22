import Foundation

struct PavbotManifest: Codable, Equatable {
    let schemaVersion: Int
    let title: String
    let generatedAt: String
    let rawBaseUrl: String
    let automations: [PavbotAutomation]
    let topics: [PavbotTopic]
    let artifacts: [PavbotArtifact]

    enum ManifestError: LocalizedError, Equatable {
        case unsupportedSchemaVersion(Int)

        var errorDescription: String? {
            switch self {
            case .unsupportedSchemaVersion(let version):
                "Unsupported manifest schema version \(version)."
            }
        }
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion
        case title
        case generatedAt
        case rawBaseUrl
        case automations
        case topics
        case artifacts
    }

    init(
        schemaVersion: Int,
        title: String,
        generatedAt: String,
        rawBaseUrl: String,
        automations: [PavbotAutomation],
        topics: [PavbotTopic],
        artifacts: [PavbotArtifact]
    ) {
        self.schemaVersion = schemaVersion
        self.title = title
        self.generatedAt = generatedAt
        self.rawBaseUrl = rawBaseUrl
        self.automations = automations
        self.topics = topics
        self.artifacts = artifacts
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        guard schemaVersion == 1 else {
            throw ManifestError.unsupportedSchemaVersion(schemaVersion)
        }
        self.schemaVersion = schemaVersion
        title = try container.decode(String.self, forKey: .title)
        generatedAt = try container.decode(String.self, forKey: .generatedAt)
        rawBaseUrl = try container.decode(String.self, forKey: .rawBaseUrl)
        automations = try container.decode([PavbotAutomation].self, forKey: .automations)
        topics = try container.decode([PavbotTopic].self, forKey: .topics)
        artifacts = try container.decode([PavbotArtifact].self, forKey: .artifacts)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(title, forKey: .title)
        try container.encode(generatedAt, forKey: .generatedAt)
        try container.encode(rawBaseUrl, forKey: .rawBaseUrl)
        try container.encode(automations, forKey: .automations)
        try container.encode(topics, forKey: .topics)
        try container.encode(artifacts, forKey: .artifacts)
    }

    var enabledAutomations: [PavbotAutomation] {
        automations.filter(\.enabled)
    }

    var availableDays: [Date] {
        let days = Set(artifacts.compactMap(\.day))
        return days.sorted(by: >)
    }

    var latestArtifact: PavbotArtifact? {
        latestArtifact(in: artifacts.filter { $0.date != nil })
    }

    var latestAutomationRun: AutomationRunSummary? {
        guard let latestArtifact else { return nil }
        let automation = matchingAutomation(for: latestArtifact)
        return AutomationRunSummary(
            time: latestArtifact.time,
            automationName: automation?.name ?? topicTitle(for: latestArtifact.topic)
        )
    }

    func artifacts(on day: Date?) -> [PavbotArtifact] {
        guard let day else { return artifacts }
        let key = day.pavbotDayString
        return artifacts.filter { $0.date == key }
    }

    func filteredArtifacts(on day: Date?, query: String) -> [PavbotArtifact] {
        let scopedArtifacts = artifacts(on: day)
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            return scopedArtifacts
        }

        return scopedArtifacts.filter { $0.matchesSearch(trimmedQuery) }
    }

    func newArtifacts(comparedTo previous: PavbotManifest?) -> [PavbotArtifact] {
        guard let previous else { return [] }
        let previousIDs = Set(previous.artifacts.map(\.id))
        return artifacts
            .filter { !previousIDs.contains($0.id) }
            .sorted { lhs, rhs in
                (lhs.date ?? "", lhs.time ?? "", lhs.path) > (rhs.date ?? "", rhs.time ?? "", rhs.path)
            }
    }

    func topicTitle(for slug: String) -> String {
        topics.first { $0.slug == slug }?.title ?? slug
    }

    func latestArtifact(for automation: PavbotAutomation) -> PavbotArtifact? {
        let topicArtifacts = artifacts.filter { $0.topic == automation.topic }
        let preferredArtifacts = topicArtifacts.filter { automation.kind.preferredArtifactTypes.contains($0.type) }
        return latestArtifact(in: preferredArtifacts.isEmpty ? topicArtifacts : preferredArtifacts)
    }

    private func latestArtifact(in artifacts: [PavbotArtifact]) -> PavbotArtifact? {
        artifacts.max { lhs, rhs in
            (lhs.date ?? "", lhs.time ?? "", lhs.path) < (rhs.date ?? "", rhs.time ?? "", rhs.path)
        }
    }

    private func matchingAutomation(for artifact: PavbotArtifact) -> PavbotAutomation? {
        enabledAutomations.first {
            $0.topic == artifact.topic && $0.kind.preferredArtifactTypes.contains(artifact.type)
        } ?? enabledAutomations.first {
            $0.topic == artifact.topic
        }
    }
}

struct AutomationRunSummary: Equatable {
    let time: String?
    let automationName: String

    var dashboardSubtitle: String {
        [time, automationName]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }
}

struct PavbotAutomation: Codable, Identifiable, Equatable, Hashable {
    let id: String
    let name: String
    let enabled: Bool
    let kind: AutomationKind
    let topic: String
    let topicPath: String
    let cadence: String
    let sourcePath: String
    let sourceUrl: String
    let output: String?
    let outputUrl: String?
}

enum AutomationKind: String, Codable, Equatable {
    case research
    case podcast
    case automation

    var preferredArtifactTypes: [ArtifactType] {
        switch self {
        case .research:
            [.run]
        case .podcast:
            [.podcastAudio]
        case .automation:
            []
        }
    }
}

struct PavbotTopic: Codable, Identifiable, Equatable, Hashable {
    var id: String { slug }

    let slug: String
    let title: String
    let path: String
    let topicFilePath: String
    let url: String
}

struct PavbotArtifact: Codable, Identifiable, Equatable, Hashable {
    let id: String
    let type: ArtifactType
    let topic: String
    let title: String
    let path: String
    let url: String
    let sizeBytes: Int
    let date: String?
    let time: String?

    var day: Date? {
        guard let date else { return nil }
        return DateFormatter.pavbotDay.date(from: date)
    }

    var viewerKind: ArtifactViewerKind {
        switch type {
        case .run, .proposal, .backlog, .index, .topic, .automationPrompt,
             .podcastScript, .podcastDraft, .podcastSources:
            return .markdown
        case .pdf, .podcastBriefPdf:
            return .pdf
        case .podcastAudio:
            return .audio
        case .podcastRender:
            return .json
        case .podcastArtifact, .unknown:
            return .file
        }
    }

    var displayDate: String {
        if let date, let time {
            return "\(date) \(time)"
        }
        return date ?? "No date"
    }

    var fileExtension: String {
        URL(fileURLWithPath: path).pathExtension.uppercased()
    }

    func resolvedURL(manifestURL: URL?) -> URL? {
        if let absoluteURL = URL(string: url), absoluteURL.scheme?.hasPrefix("http") == true {
            return absoluteURL
        }
        guard var baseURL = manifestURL?.deletingLastPathComponent() else {
            return nil
        }
        if baseURL.lastPathComponent == "public" {
            baseURL.deleteLastPathComponent()
        }
        return URL(string: url, relativeTo: baseURL)?.absoluteURL
    }

    func matchesSearch(_ query: String) -> Bool {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else { return true }

        let searchableValues = [
            id,
            type.rawValue,
            type.label,
            topic,
            title,
            path,
            url,
            date,
            time,
            displayDate,
            fileExtension
        ].compactMap { $0 }

        return searchableValues.contains {
            $0.range(of: normalizedQuery, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }
}

enum ArtifactType: Equatable, Hashable {
    case run
    case pdf
    case podcastAudio
    case podcastBriefPdf
    case podcastDraft
    case podcastRender
    case podcastScript
    case podcastSources
    case podcastArtifact
    case proposal
    case backlog
    case index
    case topic
    case automationPrompt
    case unknown(String)
}

extension ArtifactType: Codable {
    init(from decoder: Decoder) throws {
        let rawValue = try decoder.singleValueContainer().decode(String.self)
        switch rawValue {
        case "run": self = .run
        case "pdf": self = .pdf
        case "podcastAudio": self = .podcastAudio
        case "podcastBriefPdf": self = .podcastBriefPdf
        case "podcastDraft": self = .podcastDraft
        case "podcastRender": self = .podcastRender
        case "podcastScript": self = .podcastScript
        case "podcastSources": self = .podcastSources
        case "podcastArtifact": self = .podcastArtifact
        case "proposal": self = .proposal
        case "backlog": self = .backlog
        case "index": self = .index
        case "topic": self = .topic
        case "automationPrompt": self = .automationPrompt
        default: self = .unknown(rawValue)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    var rawValue: String {
        switch self {
        case .run: "run"
        case .pdf: "pdf"
        case .podcastAudio: "podcastAudio"
        case .podcastBriefPdf: "podcastBriefPdf"
        case .podcastDraft: "podcastDraft"
        case .podcastRender: "podcastRender"
        case .podcastScript: "podcastScript"
        case .podcastSources: "podcastSources"
        case .podcastArtifact: "podcastArtifact"
        case .proposal: "proposal"
        case .backlog: "backlog"
        case .index: "index"
        case .topic: "topic"
        case .automationPrompt: "automationPrompt"
        case .unknown(let value): value
        }
    }

    var label: String {
        switch self {
        case .run: "Run"
        case .pdf: "PDF"
        case .podcastAudio: "Audio"
        case .podcastBriefPdf: "Brief PDF"
        case .podcastDraft: "Draft"
        case .podcastRender: "Render"
        case .podcastScript: "Script"
        case .podcastSources: "Sources"
        case .podcastArtifact: "Podcast"
        case .proposal: "Proposal"
        case .backlog: "Backlog"
        case .index: "Index"
        case .topic: "Topic"
        case .automationPrompt: "Prompt"
        case .unknown(let value): value
        }
    }
}

enum ArtifactViewerKind: Equatable {
    case markdown
    case pdf
    case audio
    case json
    case file
}

extension JSONDecoder {
    static var pavbot: JSONDecoder {
        JSONDecoder()
    }
}

extension DateFormatter {
    static let pavbotDay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

extension Date {
    var pavbotDayString: String {
        DateFormatter.pavbotDay.string(from: self)
    }
}
