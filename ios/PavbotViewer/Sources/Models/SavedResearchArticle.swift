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

    func remove(article: ResearchNewsArticle, issue: ResearchNewsIssue) {
        let id = SavedResearchArticle(article: article, issue: issue).id
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

    func isSaved(article: ResearchNewsArticle, issue: ResearchNewsIssue) -> Bool {
        let id = SavedResearchArticle(article: article, issue: issue).id
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
        issue.topic == .polskaSwiat && (article.section == .polska || article.section == .swiat)
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
