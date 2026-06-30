import Foundation
import Observation

struct TodayHumorDigest: Codable, Equatable, Identifiable {
    let id: String
    let title: String
    let summary: String
    let generatedAt: String
    let displayTime: String
    let nextRefreshAt: String?
    let refreshIntervalHours: Int
    let items: [TodayHumorItem]
    let source: String

    var generatedAtDate: Date? {
        ISO8601DateFormatter.pavbotDate(from: generatedAt)
    }

    var nextRefreshDate: Date? {
        nextRefreshAt.flatMap(ISO8601DateFormatter.pavbotDate(from:))
    }

    var nextRefreshLabel: String {
        guard let nextRefreshDate else { return "co \(refreshIntervalHours)h" }
        return nextRefreshDate.formatted(date: .omitted, time: .shortened)
    }

    var commentHighlightCount: Int {
        items.reduce(0) { total, item in
            total + (item.commentHighlights?.count ?? 0)
        }
    }

    var originalCommentBodyCount: Int {
        items.reduce(0) { total, item in
            total + (item.commentHighlights ?? []).filter(\.hasOriginalBody).count
        }
    }

    var hasCommentHighlightsWithoutOriginalBodies: Bool {
        commentHighlightCount > originalCommentBodyCount
    }
}

struct TodayHumorItem: Codable, Equatable, Identifiable {
    let id: String
    let title: String
    let caption: String
    let sourceName: String
    let sourceURL: String
    let imageURL: String?
    let score: Int?
    let comments: Int?
    let tags: [String]
    let categoryLabel: String?
    let postText: String?
    let whyFunny: String?
    let commentHighlights: [TodayHumorCommentHighlight]?

    var sourceLink: URL? {
        URL(string: sourceURL)
    }

    var imageLink: URL? {
        guard let imageURL else { return nil }
        return URL(string: imageURL)
    }

    var scoreLabel: String? {
        guard let score else { return nil }
        if score >= 1_000 {
            return String(format: "%.1fk", Double(score) / 1_000)
        }
        return "\(score)"
    }
}

struct TodayHumorCommentHighlight: Codable, Equatable, Identifiable {
    let id: String
    let summary: String
    let originalBody: String?
    let explanation: String
    let score: Int?

    var hasOriginalBody: Bool {
        guard let originalBody = originalBody?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return false
        }
        return !originalBody.isEmpty
    }
}

struct SavedTodayHumorItem: Identifiable, Codable, Equatable {
    let item: TodayHumorItem
    let digestID: String
    let digestTitle: String
    let displayTime: String
    let savedAt: Date

    var id: String { item.id }

    var searchableText: String {
        [
            item.title,
            item.caption,
            item.sourceName,
            item.sourceURL,
            item.tags.joined(separator: " "),
            item.categoryLabel ?? "",
            item.postText ?? "",
            item.whyFunny ?? "",
            digestTitle,
            displayTime
        ]
        .joined(separator: " ")
        .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        .lowercased()
    }
}

@Observable
final class TodayHumorSavedStore {
    private let defaults: UserDefaults
    private let key = "pavbot.savedTodayHumorItems"

    private(set) var savedItems: [SavedTodayHumorItem] = []

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        savedItems = Self.load(from: defaults, key: key)
    }

    func save(
        _ item: TodayHumorItem,
        digestID: String,
        digestTitle: String,
        displayTime: String,
        savedAt: Date = Date()
    ) {
        let saved = SavedTodayHumorItem(
            item: item,
            digestID: digestID,
            digestTitle: digestTitle,
            displayTime: displayTime,
            savedAt: savedAt
        )
        savedItems.removeAll { $0.id == saved.id }
        savedItems.insert(saved, at: 0)
        sortAndSave()
    }

    func remove(_ item: TodayHumorItem) {
        savedItems.removeAll { $0.id == item.id }
        save()
    }

    func remove(_ saved: SavedTodayHumorItem) {
        savedItems.removeAll { $0.id == saved.id }
        save()
    }

    func toggle(
        _ item: TodayHumorItem,
        digestID: String,
        digestTitle: String,
        displayTime: String
    ) {
        if isSaved(item) {
            remove(item)
        } else {
            save(item, digestID: digestID, digestTitle: digestTitle, displayTime: displayTime)
        }
    }

    func isSaved(_ item: TodayHumorItem) -> Bool {
        savedItems.contains { $0.id == item.id }
    }

    func filteredItems(query: String = "") -> [SavedTodayHumorItem] {
        let normalizedQuery = query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()

        guard !normalizedQuery.isEmpty else { return savedItems }
        return savedItems.filter { $0.searchableText.contains(normalizedQuery) }
    }

    private func sortAndSave() {
        savedItems.sort { lhs, rhs in
            lhs.savedAt > rhs.savedAt
        }
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(savedItems) {
            defaults.set(data, forKey: key)
        }
    }

    private static func load(from defaults: UserDefaults, key: String) -> [SavedTodayHumorItem] {
        guard
            let data = defaults.data(forKey: key),
            let decoded = try? JSONDecoder.pavbot.decode([SavedTodayHumorItem].self, from: data)
        else {
            return []
        }
        return decoded.sorted { $0.savedAt > $1.savedAt }
    }
}
