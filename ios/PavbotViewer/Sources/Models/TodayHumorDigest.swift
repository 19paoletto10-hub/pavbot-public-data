import Foundation

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
