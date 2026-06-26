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

    var generatedAtDate: Date? {
        ISO8601DateFormatter.pavbotDate(from: generatedAt)
    }

    var latestAutomationRun: AutomationRunSummary? {
        guard let latestArtifact else { return nil }
        let automation = matchingAutomation(for: latestArtifact)
        return AutomationRunSummary(
            time: latestArtifact.time,
            automationName: automation?.name ?? topicTitle(for: latestArtifact.topic)
        )
    }

    var automationArtifactGroups: [AutomationArtifactGroup] {
        enabledAutomations.map {
            AutomationArtifactGroup(automation: $0, artifacts: scopedArtifacts(for: $0))
        }
    }

    func automationArtifactGroup(for id: String?) -> AutomationArtifactGroup? {
        guard let id else { return nil }
        return automationArtifactGroups.first { $0.id == id }
    }

    func automationArtifactGroup(for route: ArtifactNotificationRoute?) -> AutomationArtifactGroup? {
        guard let route else { return nil }
        var bestGroup: AutomationArtifactGroup?
        var bestScore = 0

        for group in automationArtifactGroups {
            let score = group.routeMatchScore(route)
            if score > bestScore {
                bestGroup = group
                bestScore = score
            }
        }

        return bestGroup
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

    func filteredArtifacts(for route: ArtifactNotificationRoute?) -> [PavbotArtifact] {
        guard let route else { return artifacts }
        if !route.artifactIDs.isEmpty {
            let order = Dictionary(uniqueKeysWithValues: route.artifactIDs.enumerated().map { ($0.element, $0.offset) })
            return artifacts
                .filter { order[$0.id] != nil }
                .sorted { (order[$0.id] ?? Int.max) < (order[$1.id] ?? Int.max) }
        }

        return artifacts.filter { artifact in
            if let topic = route.topic, artifact.topic != topic {
                return false
            }
            if let date = route.date, artifact.date != date {
                return false
            }
            return true
        }
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

    func newAutomations(comparedTo previous: PavbotManifest?) -> [PavbotAutomation] {
        guard let previous else { return [] }
        let previousIDs = Set(previous.automations.map(\.id))
        return enabledAutomations.filter { !previousIDs.contains($0.id) }
    }

    func isOlder(than other: PavbotManifest) -> Bool {
        guard let generatedAtDate, let otherGeneratedAtDate = other.generatedAtDate else {
            return false
        }
        return generatedAtDate < otherGeneratedAtDate
    }

    func topicTitle(for slug: String) -> String {
        topics.first { $0.slug == slug }?.title ?? slug
    }

    func latestArtifact(for automation: PavbotAutomation) -> PavbotArtifact? {
        let topicArtifacts = artifacts.filter { $0.topic == automation.topic }
        for artifactType in automation.kind.preferredArtifactTypes {
            let preferredArtifacts = topicArtifacts.filter { $0.type == artifactType }
            if let latest = latestArtifact(in: preferredArtifacts) {
                return latest
            }
        }
        return latestArtifact(in: topicArtifacts)
    }

    private func scopedArtifacts(for automation: PavbotAutomation) -> [PavbotArtifact] {
        let topicArtifacts = artifacts.filter { $0.topic == automation.topic }
        let preferredTypes = automation.kind.preferredArtifactTypes
        let filteredArtifacts = preferredTypes.isEmpty
            ? topicArtifacts
            : topicArtifacts.filter { preferredTypes.contains($0.type) }

        return filteredArtifacts.sorted(by: PavbotArtifact.automationDisplaySort)
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

struct AutomationArtifactGroup: Identifiable, Equatable, Hashable {
    let automation: PavbotAutomation
    let artifacts: [PavbotArtifact]

    var id: String { automation.id }

    var latestArtifact: PavbotArtifact? {
        artifacts.first
    }

    var datedArtifacts: [PavbotArtifact] {
        artifacts.filter { $0.date != nil }
    }

    var otherArtifacts: [PavbotArtifact] {
        artifacts.filter { $0.date == nil }
    }

    var days: [Date] {
        Set(datedArtifacts.compactMap(\.day)).sorted(by: >)
    }

    func artifacts(on day: Date, matching route: ArtifactNotificationRoute? = nil) -> [PavbotArtifact] {
        let dayString = day.pavbotDayString
        var dayArtifacts = artifacts.filter { $0.date == dayString }

        if let route, !route.artifactIDs.isEmpty {
            let routeIDs = Set(route.artifactIDs)
            dayArtifacts = dayArtifacts.filter { routeIDs.contains($0.id) }
        }

        return dayArtifacts.sorted(by: PavbotArtifact.automationDisplaySort)
    }

    func podcastPackage(on day: Date, matching route: ArtifactNotificationRoute? = nil) -> PodcastArtifactPackage? {
        let dayArtifacts = artifacts(on: day, matching: route)
        let package = PodcastArtifactPackage(artifacts: dayArtifacts)
        return package.hasPodcastContent ? package : nil
    }

    func routeMatchScore(_ route: ArtifactNotificationRoute) -> Int {
        if let topic = route.topic, topic != automation.topic {
            return 0
        }

        if !route.artifactIDs.isEmpty {
            let routeIDs = Set(route.artifactIDs)
            let matchingIDs = artifacts.filter { routeIDs.contains($0.id) }.count
            if matchingIDs > 0 {
                return 100 + matchingIDs
            }
        }

        if let date = route.date, artifacts.contains(where: { $0.date == date }) {
            return 10
        }

        return route.topic == automation.topic ? 1 : 0
    }
}

struct PodcastArtifactPackage: Equatable, Hashable {
    let primaryAudio: PavbotArtifact?
    let briefPDF: PavbotArtifact?
    let audioVariants: [PavbotArtifact]

    init(artifacts: [PavbotArtifact]) {
        primaryAudio = artifacts.first { $0.type == .podcastAudio }
        briefPDF = artifacts.first { $0.type == .podcastBriefPdf }
        audioVariants = artifacts.filter { $0.type == .podcastAudioVariant }
    }

    var hasPodcastContent: Bool {
        primaryAudio != nil || briefPDF != nil || !audioVariants.isEmpty
    }

    var hasAudio: Bool {
        primaryAudio != nil || !audioVariants.isEmpty
    }

    var isMissingBriefPDF: Bool {
        hasAudio && briefPDF == nil
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
    case researchAudio
    case automation

    var preferredArtifactTypes: [ArtifactType] {
        switch self {
        case .research:
            [.researchData, .run, .pdf]
        case .podcast:
            [.podcastAudio, .podcastAudioVariant, .podcastScript, .podcastBriefPdf]
        case .researchAudio:
            [.mobileNewsData, .podcastScript, .podcastAudioVariant, .podcastAudio, .pdf, .run]
        case .automation:
            [.pulseNewsData, .run, .proposal, .backlog, .index]
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
        case .podcastAudio, .podcastAudioVariant:
            return .audio
        case .podcastRender, .podcastTtsVariants, .jobsData, .researchData, .mobileNewsData, .pulseNewsData:
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

    static func automationDisplaySort(_ lhs: PavbotArtifact, _ rhs: PavbotArtifact) -> Bool {
        (lhs.date ?? "", lhs.time ?? "", lhs.path) > (rhs.date ?? "", rhs.time ?? "", rhs.path)
    }
}

enum ArtifactType: Equatable, Hashable {
    case run
    case pdf
    case podcastAudio
    case podcastAudioVariant
    case podcastBriefPdf
    case podcastDraft
    case podcastRender
    case podcastScript
    case podcastSources
    case podcastTtsVariants
    case podcastArtifact
    case jobsData
    case researchData
    case mobileNewsData
    case pulseNewsData
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
        case "podcastAudioVariant": self = .podcastAudioVariant
        case "podcastBriefPdf": self = .podcastBriefPdf
        case "podcastDraft": self = .podcastDraft
        case "podcastRender": self = .podcastRender
        case "podcastScript": self = .podcastScript
        case "podcastSources": self = .podcastSources
        case "podcastTtsVariants": self = .podcastTtsVariants
        case "podcastArtifact": self = .podcastArtifact
        case "jobsData": self = .jobsData
        case "researchData": self = .researchData
        case "mobileNewsData": self = .mobileNewsData
        case "pulseNewsData": self = .pulseNewsData
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
        case .podcastAudioVariant: "podcastAudioVariant"
        case .podcastBriefPdf: "podcastBriefPdf"
        case .podcastDraft: "podcastDraft"
        case .podcastRender: "podcastRender"
        case .podcastScript: "podcastScript"
        case .podcastSources: "podcastSources"
        case .podcastTtsVariants: "podcastTtsVariants"
        case .podcastArtifact: "podcastArtifact"
        case .jobsData: "jobsData"
        case .researchData: "researchData"
        case .mobileNewsData: "mobileNewsData"
        case .pulseNewsData: "pulseNewsData"
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
        case .podcastAudioVariant: "Audio variant"
        case .podcastBriefPdf: "Brief PDF"
        case .podcastDraft: "Draft"
        case .podcastRender: "Render"
        case .podcastScript: "Script"
        case .podcastSources: "Sources"
        case .podcastTtsVariants: "TTS variants"
        case .podcastArtifact: "Podcast"
        case .jobsData: "Jobs data"
        case .researchData: "Research data"
        case .mobileNewsData: "Mobile news data"
        case .pulseNewsData: "Pulse news data"
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

extension ISO8601DateFormatter {
    static func pavbotDate(from value: String) -> Date? {
        if let date = fractionalPavbot.date(from: value) {
            return date
        }
        return standardPavbot.date(from: value)
    }

    private static let fractionalPavbot: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let standardPavbot: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
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

struct ArtifactNotificationRoute: Equatable, Hashable, Sendable {
    let topic: String?
    let date: String?
    let artifactIDs: [String]

    init(topic: String?, date: String?, artifactIDs: [String]) {
        self.topic = topic?.nilIfBlank
        self.date = date?.nilIfBlank
        self.artifactIDs = artifactIDs.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    init?(userInfo: [AnyHashable: Any]) {
        let topic = userInfo["artifactTopic"] as? String
        let date = userInfo["artifactDate"] as? String
        let artifactIDs = Self.stringArray(from: userInfo["artifactIDs"])
        guard topic?.nilIfBlank != nil || date?.nilIfBlank != nil || !artifactIDs.isEmpty else {
            return nil
        }
        self.init(topic: topic, date: date, artifactIDs: artifactIDs)
    }

    init(artifacts: [PavbotArtifact]) {
        let topics = Set(artifacts.map(\.topic).filter { !$0.isEmpty })
        let dates = Set(artifacts.compactMap(\.date).filter { !$0.isEmpty })
        self.init(
            topic: topics.count == 1 ? topics.first : nil,
            date: dates.count == 1 ? dates.first : nil,
            artifactIDs: artifacts.map(\.id)
        )
    }

    var userInfo: [String: Any] {
        var values: [String: Any] = [:]
        if let topic {
            values["artifactTopic"] = topic
        }
        if let date {
            values["artifactDate"] = date
        }
        if !artifactIDs.isEmpty {
            values["artifactIDs"] = artifactIDs
        }
        return values
    }

    var displayTitle: String {
        if let topic, let date {
            return "\(topic) · \(date)"
        }
        if let topic {
            return topic
        }
        if let date {
            return date
        }
        return "Notification files"
    }

    private static func stringArray(from value: Any?) -> [String] {
        if let strings = value as? [String] {
            return strings
        }
        if let values = value as? [Any] {
            return values.compactMap { $0 as? String }
        }
        if let string = value as? String {
            return [string]
        }
        return []
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
