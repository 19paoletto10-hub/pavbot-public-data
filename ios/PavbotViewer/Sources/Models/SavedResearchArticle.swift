import Foundation
import Observation

struct SavedResearchArticle: Identifiable, Codable, Equatable {
    let article: ResearchNewsArticle
    let topic: ReportTopicKind
    let issuePackageKey: String
    let issueDate: String?
    let issueTime: String?
    let savedAt: Date

    var id: String {
        [topic.rawValue, issuePackageKey, article.id].joined(separator: "|")
    }

    var displayDate: String {
        [issueDate, issueTime]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    var searchableText: String {
        [
            topic.title,
            article.title,
            article.summary,
            article.body,
            article.section.rawValue,
            article.tags.joined(separator: " "),
            article.sources.map(\.title).joined(separator: " "),
            displayDate
        ]
        .joined(separator: " ")
        .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        .lowercased()
    }

    init(article: ResearchNewsArticle, issue: ResearchNewsIssue, savedAt: Date = Date()) {
        self.article = article
        self.topic = issue.topic
        self.issuePackageKey = issue.packageKey
        self.issueDate = issue.date
        self.issueTime = issue.time
        self.savedAt = savedAt
    }

    init(article: MobileNewsArticle, magazine: MobileNewsMagazine, savedAt: Date = Date()) {
        self.article = Self.researchArticle(from: article)
        self.topic = .aktualne
        self.issuePackageKey = Self.mobileIssuePackageKey(for: magazine)
        self.issueDate = magazine.runDate
        self.issueTime = magazine.runTime
        self.savedAt = savedAt
    }

    private static func mobileIssuePackageKey(for magazine: MobileNewsMagazine) -> String {
        [magazine.runDate, magazine.runTime]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "-")
    }

    private static func researchArticle(from article: MobileNewsArticle) -> ResearchNewsArticle {
        let analysis = article.analysis.trimmingCharacters(in: .whitespacesAndNewlines)
        let whyItMatters = article.whyItMatters.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = ([article.lead] + article.facts + [analysis, whyItMatters])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")

        return ResearchNewsArticle(
            id: article.id,
            title: article.title,
            section: mobileSection(from: article.section),
            body: body,
            summary: article.lead,
            whatHappened: article.lead,
            whyItMatters: whyItMatters.isEmpty ? nil : whyItMatters,
            deeperAnalysis: analysis.isEmpty ? nil : [analysis],
            contextPoints: article.facts.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty },
            sources: article.sources,
            priority: article.priority,
            tags: article.tags
        )
    }

    private static func mobileSection(from section: String) -> ResearchNewsSection {
        let normalized = section
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()

        if normalized.contains("polska") {
            return .polska
        }
        if normalized.contains("polityka") {
            return .polityka
        }
        if normalized.contains("swiat")
            || normalized.contains("zagranicz")
            || normalized.contains("miedzynarod") {
            return .swiat
        }
        if normalized.contains("bezpieczen") {
            return .bezpieczenstwo
        }
        if normalized.contains("gospodar") {
            return .gospodarka
        }
        if normalized.contains("pogod") {
            return .pogoda
        }
        if normalized.contains("technolog") || normalized.contains("tech") {
            return .technologia
        }
        return .inne
    }
}

@Observable
final class SavedResearchArticleStore {
    private let defaults: UserDefaults
    private let key = "pavbot.savedResearchArticles"

    private(set) var savedArticles: [SavedResearchArticle] = []

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        savedArticles = Self.load(from: defaults, key: key)
    }

    func save(article: ResearchNewsArticle, issue: ResearchNewsIssue, savedAt: Date = Date()) {
        guard Self.canSave(article: article, issue: issue) else { return }
        let saved = SavedResearchArticle(article: article, issue: issue, savedAt: savedAt)
        savedArticles.removeAll { $0.id == saved.id }
        savedArticles.insert(saved, at: 0)
        sortAndPersist()
    }

    func save(article: MobileNewsArticle, magazine: MobileNewsMagazine, savedAt: Date = Date()) {
        guard Self.canSave(article: article, magazine: magazine) else { return }
        let saved = SavedResearchArticle(article: article, magazine: magazine, savedAt: savedAt)
        savedArticles.removeAll { $0.id == saved.id }
        savedArticles.insert(saved, at: 0)
        sortAndPersist()
    }

    func remove(article: ResearchNewsArticle, issue: ResearchNewsIssue) {
        let id = SavedResearchArticle(article: article, issue: issue).id
        savedArticles.removeAll { $0.id == id }
        persist()
    }

    func remove(article: MobileNewsArticle, magazine: MobileNewsMagazine) {
        let id = SavedResearchArticle(article: article, magazine: magazine).id
        savedArticles.removeAll { $0.id == id }
        persist()
    }

    func remove(_ saved: SavedResearchArticle) {
        savedArticles.removeAll { $0.id == saved.id }
        persist()
    }

    func toggle(article: ResearchNewsArticle, issue: ResearchNewsIssue) {
        if isSaved(article: article, issue: issue) {
            remove(article: article, issue: issue)
        } else {
            save(article: article, issue: issue)
        }
    }

    func toggle(article: MobileNewsArticle, magazine: MobileNewsMagazine) {
        if isSaved(article: article, magazine: magazine) {
            remove(article: article, magazine: magazine)
        } else {
            save(article: article, magazine: magazine)
        }
    }

    func isSaved(article: ResearchNewsArticle, issue: ResearchNewsIssue) -> Bool {
        let id = SavedResearchArticle(article: article, issue: issue).id
        return savedArticles.contains { $0.id == id }
    }

    func isSaved(article: MobileNewsArticle, magazine: MobileNewsMagazine) -> Bool {
        let id = SavedResearchArticle(article: article, magazine: magazine).id
        return savedArticles.contains { $0.id == id }
    }

    func filteredArticles(query: String = "", topic: ReportTopicKind? = nil, section: ResearchNewsSection? = nil) -> [SavedResearchArticle] {
        let normalizedQuery = query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()

        return savedArticles.filter { saved in
            let topicMatches = topic.map { saved.topic == $0 } ?? true
            let sectionMatches = section.map { saved.article.section == $0 } ?? true
            let queryMatches = normalizedQuery.isEmpty || saved.searchableText.contains(normalizedQuery)
            return topicMatches && sectionMatches && queryMatches
        }
    }

    static func canSave(article: ResearchNewsArticle, issue: ResearchNewsIssue) -> Bool {
        issue.topic == .techNews || issue.topic == .polskaSwiat
    }

    static func canSave(article: MobileNewsArticle, magazine: MobileNewsMagazine) -> Bool {
        magazine.topic == ReportTopicKind.aktualne.topic
    }

    private func sortAndPersist() {
        savedArticles.sort { lhs, rhs in
            lhs.savedAt > rhs.savedAt
        }
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(savedArticles) {
            defaults.set(data, forKey: key)
        }
    }

    private static func load(from defaults: UserDefaults, key: String) -> [SavedResearchArticle] {
        guard
            let data = defaults.data(forKey: key),
            let decoded = try? JSONDecoder.pavbot.decode([SavedResearchArticle].self, from: data)
        else {
            return []
        }
        return decoded.sorted { $0.savedAt > $1.savedAt }
    }
}
