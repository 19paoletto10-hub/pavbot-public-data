import CoreGraphics
import Foundation
import Observation

enum TodayLiveTopicScope: String, CaseIterable, Identifiable, Codable {
    case pulse
    case poland
    case world

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pulse:
            "Puls dnia"
        case .poland:
            "Tym żyje Polska"
        case .world:
            "Tym żyje świat"
        }
    }

    var subtitle: String {
        switch self {
        case .pulse:
            "Najświeższe tematy z ostatnich godzin"
        case .poland:
            "Dwa najważniejsze krajowe tematy z magazynu 10:15"
        case .world:
            "Dwa najważniejsze światowe tematy z magazynu 10:15"
        }
    }

    var systemImage: String {
        switch self {
        case .pulse:
            "bolt.horizontal.circle.fill"
        case .poland:
            "flag.fill"
        case .world:
            "globe.europe.africa.fill"
        }
    }
}

struct TodayLiveTopicGroup: Identifiable, Equatable {
    let scope: TodayLiveTopicScope
    let topics: [TodayLiveTopic]

    var id: TodayLiveTopicScope { scope }
    var title: String { scope.title }
    var subtitle: String { scope.subtitle }
}

struct TodayLiveTopic: Identifiable, Equatable, Codable {
    let id: String
    let scope: TodayLiveTopicScope
    let section: String
    let title: String
    let lead: String
    let keyFacts: [String]
    let reactions: [String]
    let whyItMatters: String
    let context: String
    let watchNext: [String]
    let sources: [ResearchNewsSource]
    let tags: [String]
    let priority: String

    var sourceCountLabel: String {
        "\(sources.count) źr."
    }
}

struct TodayLiveTopicPair: Identifiable, Equatable {
    let topics: [TodayLiveTopic]

    var id: String {
        topics.map(\.id).joined(separator: "|")
    }
}

struct TodayLiveTopicSelection: Identifiable, Equatable {
    let topic: TodayLiveTopic
    let source: TodayLiveTopicsSource
    let displayDate: String

    var id: String {
        [source.rawValue, displayDate, topic.id].joined(separator: "|")
    }
}

enum TodayLiveTopicsSource: String, Equatable, Codable {
    case pulseNews
    case mobileNews

    var label: String {
        switch self {
        case .pulseNews:
            "Puls dnia 3h"
        case .mobileNews:
            "Dane fallbackowe z magazynu 10:15"
        }
    }

    var isFallback: Bool {
        self == .mobileNews
    }
}

struct TodayLiveTopicsCarouselState: Equatable {
    var selectedTopic: TodayLiveTopic?
    var reduceMotionEnabled = false

    var isAutoScrollPaused: Bool {
        selectedTopic != nil || reduceMotionEnabled
    }
}

enum TodayLiveTopicsSwipeAction: Equatable {
    case previous
    case next

    var pageOffset: Int {
        switch self {
        case .previous:
            -1
        case .next:
            1
        }
    }
}

struct TodayLiveTopicsSwipeDecision: Equatable {
    static let minimumHorizontalDistance: CGFloat = 44
    static let horizontalDominanceRatio: CGFloat = 1.15

    static func action(
        translation: CGSize,
        predictedEndTranslation: CGSize,
        pageCount: Int,
        detailIsOpen: Bool = false
    ) -> TodayLiveTopicsSwipeAction? {
        guard pageCount > 1, !detailIsOpen else { return nil }

        let candidate = abs(predictedEndTranslation.width) > abs(translation.width)
            ? predictedEndTranslation
            : translation
        let horizontalDistance = max(abs(translation.width), abs(predictedEndTranslation.width))
        let verticalDistance = max(abs(translation.height), abs(predictedEndTranslation.height))

        guard horizontalDistance >= minimumHorizontalDistance else { return nil }
        guard horizontalDistance > verticalDistance * horizontalDominanceRatio else { return nil }

        return candidate.width < 0 ? .next : .previous
    }
}

struct TodayLiveTopicsPageAdvance: Equatable {
    static func nextIndex(currentIndex: Int, pageCount: Int, offset: Int, detailIsOpen: Bool = false) -> Int? {
        guard pageCount > 1, !detailIsOpen else { return nil }
        let boundedCurrent = min(max(currentIndex, 0), pageCount - 1)
        return (boundedCurrent + offset + pageCount) % pageCount
    }
}

struct TodayLiveTopicsSnapshot: Identifiable, Equatable {
    let id: String
    let displayDate: String
    let source: TodayLiveTopicsSource
    let headline: String
    let summary: String
    let pairs: [TodayLiveTopicPair]
    let poland: TodayLiveTopicGroup
    let world: TodayLiveTopicGroup

    var sourceLabel: String { source.label }
    var isFallback: Bool { source.isFallback }

    init(magazine: MobileNewsMagazine) {
        let polandGroup = TodayLiveTopicGroup(
            scope: .poland,
            topics: Self.topics(from: magazine, scope: .poland)
        )
        let worldGroup = TodayLiveTopicGroup(
            scope: .world,
            topics: Self.topics(from: magazine, scope: .world)
        )

        id = magazine.id
        displayDate = magazine.displayDate
        source = .mobileNews
        headline = "Puls Dnia"
        summary = magazine.leadParagraphs.first ?? magazine.headline
        poland = polandGroup
        world = worldGroup
        pairs = Self.makePairs(from: polandGroup.topics + worldGroup.topics)
    }

    init(digest: PulseNewsDigest) {
        id = digest.id
        displayDate = digest.displayDate
        source = .pulseNews
        headline = digest.headline
        summary = digest.summary
        let topics = digest.items.map(Self.topic(from:))
        pairs = Self.makePairs(from: topics)
        poland = TodayLiveTopicGroup(
            scope: .poland,
            topics: topics.filter { topic in
                Self.sectionMatches(topic.section, scope: .poland)
            }
        )
        world = TodayLiveTopicGroup(
            scope: .world,
            topics: topics.filter { topic in
                Self.sectionMatches(topic.section, scope: .world)
            }
        )
    }

    private init(
        id: String,
        displayDate: String,
        source: TodayLiveTopicsSource,
        headline: String,
        summary: String,
        pairs: [TodayLiveTopicPair],
        poland: TodayLiveTopicGroup,
        world: TodayLiveTopicGroup
    ) {
        self.id = id
        self.displayDate = displayDate
        self.source = source
        self.headline = headline
        self.summary = summary
        self.pairs = pairs
        self.poland = poland
        self.world = world
    }

    var groups: [TodayLiveTopicGroup] {
        [poland, world].filter { !$0.topics.isEmpty }
    }

    var allTopics: [TodayLiveTopic] {
        pairs.flatMap(\.topics)
    }

    func removingSavedTopics(in store: TodayLiveTopicSavedStore) -> TodayLiveTopicsSnapshot {
        let visibleTopics = allTopics.filter { !store.isSaved($0) }
        let visiblePoland = TodayLiveTopicGroup(
            scope: .poland,
            topics: poland.topics.filter { !store.isSaved($0) }
        )
        let visibleWorld = TodayLiveTopicGroup(
            scope: .world,
            topics: world.topics.filter { !store.isSaved($0) }
        )
        let savedSignature = store.savedTopics
            .map(\.id)
            .sorted()
            .joined(separator: "|")

        return TodayLiveTopicsSnapshot(
            id: "\(id)-saved-filter-\(savedSignature)",
            displayDate: displayDate,
            source: source,
            headline: headline,
            summary: summary,
            pairs: Self.makePairs(from: visibleTopics),
            poland: visiblePoland,
            world: visibleWorld
        )
    }

    private static func topics(from magazine: MobileNewsMagazine, scope: TodayLiveTopicScope) -> [TodayLiveTopic] {
        let articles = magazine.sections
            .filter { section in sectionMatches(section.title, scope: scope) }
            .flatMap { section in
                section.articles.map { article in
                    TodayLiveTopic(
                        id: "\(scope.rawValue)-\(article.id)",
                        scope: scope,
                        section: article.section,
                        title: article.title,
                        lead: article.lead,
                        keyFacts: Array(article.facts.prefix(3)),
                        reactions: reactionLines(from: article),
                        whyItMatters: article.whyItMatters,
                        context: article.analysis,
                        watchNext: ["Obserwuj kolejne komunikaty i aktualizacje źródeł dla tego tematu."],
                        sources: article.sources,
                        tags: article.tags,
                        priority: article.priority
                    )
                }
            }

        return articles
            .sorted { lhs, rhs in
                let leftScore = priorityScore(lhs.priority)
                let rightScore = priorityScore(rhs.priority)
                if leftScore != rightScore { return leftScore < rightScore }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
            .prefix(2)
            .map { $0 }
    }

    private static func topic(from item: PulseNewsItem) -> TodayLiveTopic {
        TodayLiveTopic(
            id: "pulse-\(item.id)",
            scope: .pulse,
            section: item.section,
            title: item.title,
            lead: item.lead,
            keyFacts: item.keyFacts,
            reactions: item.reactions,
            whyItMatters: item.whyItMatters,
            context: item.context,
            watchNext: item.watchNext,
            sources: item.sources,
            tags: item.tags,
            priority: item.priority
        )
    }

    private static func makePairs(from topics: [TodayLiveTopic]) -> [TodayLiveTopicPair] {
        var pairs: [TodayLiveTopicPair] = []
        var index = 0
        while index < topics.count {
            let nextIndex = min(index + 2, topics.count)
            pairs.append(TodayLiveTopicPair(topics: Array(topics[index..<nextIndex])))
            index += 2
        }
        return pairs
    }

    private static func sectionMatches(_ title: String, scope: TodayLiveTopicScope) -> Bool {
        let normalized = title.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).lowercased()
        switch scope {
        case .pulse:
            return true
        case .poland:
            return normalized.contains("polska") || normalized.contains("polityka")
        case .world:
            return normalized.contains("swiat") || normalized.contains("zagraniczne") || normalized.contains("miedzynarodowe")
        }
    }

    private static func reactionLines(from article: MobileNewsArticle) -> [String] {
        let cleaned = article.analysis.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            return ["Reakcje będą zależeć od kolejnych decyzji, komunikatów i potwierdzeń ze źródeł."]
        }
        return [cleaned]
    }

    private static func priorityScore(_ value: String) -> Int {
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "critical", "high", "wysoki":
            0
        case "medium", "średni", "sredni":
            1
        default:
            2
        }
    }
}

struct TodayLiveTopicsCarouselLayout: Equatable {
    let cardCount: Int
    let compactWidth: Bool

    var cardSpacing: CGFloat { compactWidth ? 12 : 14 }
    var cardHeight: CGFloat { compactWidth ? 198 : 182 }
    var pageHeight: CGFloat {
        guard cardCount > 0 else { return 0 }
        return CGFloat(cardCount) * cardHeight + CGFloat(max(cardCount - 1, 0)) * cardSpacing
    }
}

struct PulseDayHistoryRunPresentation: Equatable {
    static let previewLimit = 4

    let snapshot: TodayLiveTopicsSnapshot

    var allTopics: [TodayLiveTopic] {
        snapshot.allTopics
    }

    var previewTopics: [TodayLiveTopic] {
        Array(allTopics.prefix(Self.previewLimit))
    }

    var hiddenTopicCount: Int {
        max(allTopics.count - previewTopics.count, 0)
    }

    var previewStatusText: String {
        guard hiddenTopicCount > 0 else {
            return "\(allTopics.count) tematów"
        }
        return "Pokazano \(previewTopics.count) z \(allTopics.count)"
    }

    var openAllButtonTitle: String {
        "Zobacz wszystkie artykuły"
    }

    var sectionTitles: [String] {
        var seen = Set<String>()
        let sections = allTopics
            .map { $0.section.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { section in
                let key = section.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).lowercased()
                return seen.insert(key).inserted
            }

        return sections.sorted { lhs, rhs in
            let leftRank = Self.sectionRank(lhs)
            let rightRank = Self.sectionRank(rhs)
            if leftRank != rightRank { return leftRank < rightRank }
            return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
        }
    }

    func topics(in section: String?) -> [TodayLiveTopic] {
        guard let section, !section.isEmpty else { return allTopics }
        let normalizedSection = Self.normalized(section)
        return allTopics.filter { Self.normalized($0.section) == normalizedSection }
    }

    private static func normalized(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
    }

    private static func sectionRank(_ section: String) -> Int {
        let normalized = normalized(section)
        let ordered = [
            "polska",
            "swiat",
            "polityka",
            "bezpieczenstwo",
            "gospodarka",
            "technologia",
            "alerty"
        ]
        return ordered.firstIndex(where: { normalized.contains($0) }) ?? ordered.count
    }
}

struct SavedTodayLiveTopic: Identifiable, Codable, Equatable {
    let topic: TodayLiveTopic
    let source: TodayLiveTopicsSource
    let displayDate: String
    let savedAt: Date

    var id: String { topic.id }
    var sourceLabel: String { source.label }

    var searchableText: String {
        [
            topic.title,
            topic.lead,
            topic.section,
            topic.keyFacts.joined(separator: " "),
            topic.reactions.joined(separator: " "),
            topic.whyItMatters,
            topic.context,
            topic.watchNext.joined(separator: " "),
            topic.tags.joined(separator: " "),
            displayDate,
            sourceLabel
        ]
        .joined(separator: " ")
        .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        .lowercased()
    }

    private enum CodingKeys: String, CodingKey {
        case topic
        case source
        case displayDate
        case savedAt
        case archivedAt
    }

    init(topic: TodayLiveTopic, source: TodayLiveTopicsSource, displayDate: String, savedAt: Date) {
        self.topic = topic
        self.source = source
        self.displayDate = displayDate
        self.savedAt = savedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        topic = try container.decode(TodayLiveTopic.self, forKey: .topic)
        source = try container.decode(TodayLiveTopicsSource.self, forKey: .source)
        displayDate = try container.decode(String.self, forKey: .displayDate)
        savedAt = try container.decodeIfPresent(Date.self, forKey: .savedAt)
            ?? container.decode(Date.self, forKey: .archivedAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(topic, forKey: .topic)
        try container.encode(source, forKey: .source)
        try container.encode(displayDate, forKey: .displayDate)
        try container.encode(savedAt, forKey: .savedAt)
    }
}

@Observable
final class TodayLiveTopicSavedStore {
    private let defaults: UserDefaults
    private let key = "pavbot.savedTodayLiveTopics"
    private let legacyKey = "pavbot.archivedTodayLiveTopics"

    private(set) var savedTopics: [SavedTodayLiveTopic] = []

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if defaults.data(forKey: key) == nil, defaults.data(forKey: legacyKey) != nil {
            savedTopics = Self.load(from: defaults, key: legacyKey)
            save()
            defaults.removeObject(forKey: legacyKey)
        } else {
            savedTopics = Self.load(from: defaults, key: key)
        }
    }

    func save(
        _ topic: TodayLiveTopic,
        source: TodayLiveTopicsSource,
        displayDate: String,
        savedAt: Date = Date()
    ) {
        let saved = SavedTodayLiveTopic(
            topic: topic,
            source: source,
            displayDate: displayDate,
            savedAt: savedAt
        )
        savedTopics.removeAll { $0.id == saved.id }
        savedTopics.insert(saved, at: 0)
        sortAndSave()
    }

    func remove(_ topic: TodayLiveTopic) {
        savedTopics.removeAll { $0.id == topic.id }
        save()
    }

    func toggle(_ topic: TodayLiveTopic, source: TodayLiveTopicsSource, displayDate: String) {
        if isSaved(topic) {
            remove(topic)
        } else {
            save(topic, source: source, displayDate: displayDate)
        }
    }

    func isSaved(_ topic: TodayLiveTopic) -> Bool {
        savedTopics.contains { $0.id == topic.id }
    }

    func filteredTopics(query: String = "", scope: TodayLiveTopicScope? = nil) -> [SavedTodayLiveTopic] {
        let normalizedQuery = query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()

        return savedTopics.filter { saved in
            let matchesScope = scope.map { saved.topic.scope == $0 } ?? true
            let matchesQuery = normalizedQuery.isEmpty || saved.searchableText.contains(normalizedQuery)
            return matchesScope && matchesQuery
        }
    }

    private func sortAndSave() {
        savedTopics.sort { lhs, rhs in
            lhs.savedAt > rhs.savedAt
        }
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(savedTopics) {
            defaults.set(data, forKey: key)
        }
    }

    private static func load(from defaults: UserDefaults, key: String) -> [SavedTodayLiveTopic] {
        guard
            let data = defaults.data(forKey: key),
            let decoded = try? JSONDecoder.pavbot.decode([SavedTodayLiveTopic].self, from: data)
        else {
            return []
        }
        return decoded.sorted { $0.savedAt > $1.savedAt }
    }
}

struct CachedPulseNewsRun: Identifiable, Codable, Equatable {
    let digest: PulseNewsDigest
    let cachedAt: Date

    var id: String { digest.id }
    var snapshot: TodayLiveTopicsSnapshot { TodayLiveTopicsSnapshot(digest: digest) }
}

@Observable
final class PulseNewsHistoryStore {
    static let retentionInterval: TimeInterval = 48 * 60 * 60

    private let defaults: UserDefaults
    private let key = "pavbot.cachedPulseNewsRuns"
    private let now: () -> Date

    private(set) var runs: [CachedPulseNewsRun] = []

    init(defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.now = now
        runs = Self.load(from: defaults, key: key)
        prune()
    }

    var latest: CachedPulseNewsRun? {
        runs.first
    }

    var snapshots: [TodayLiveTopicsSnapshot] {
        runs.map(\.snapshot)
    }

    func save(_ digest: PulseNewsDigest, cachedAt: Date? = nil) {
        let cached = CachedPulseNewsRun(digest: digest, cachedAt: cachedAt ?? now())
        runs.removeAll { $0.id == cached.id }
        runs.append(cached)
        pruneAndPersist()
    }

    func prune() {
        pruneAndPersist()
    }

    private func pruneAndPersist() {
        let referenceNow = now()
        runs = runs
            .filter { cached in
                referenceNow.timeIntervalSince(Self.referenceDate(for: cached)) <= Self.retentionInterval
            }
            .sorted { lhs, rhs in
                Self.referenceDate(for: lhs) > Self.referenceDate(for: rhs)
            }
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(runs) {
            defaults.set(data, forKey: key)
        }
    }

    private static func load(from defaults: UserDefaults, key: String) -> [CachedPulseNewsRun] {
        guard
            let data = defaults.data(forKey: key),
            let decoded = try? JSONDecoder.pavbot.decode([CachedPulseNewsRun].self, from: data)
        else {
            return []
        }
        return decoded
    }

    private static func referenceDate(for cached: CachedPulseNewsRun) -> Date {
        parsedRunDate(for: cached.digest) ?? cached.cachedAt
    }

    private static func parsedRunDate(for digest: PulseNewsDigest) -> Date? {
        let date = digest.runDate.trimmingCharacters(in: .whitespacesAndNewlines)
        let time = digest.runTime.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !date.isEmpty, !time.isEmpty else { return nil }
        return runDateFormatter.date(from: "\(date) \(time)")
    }

    private static let runDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Europe/Warsaw")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()
}
