import Foundation

struct PulseNewsDigest: Codable, Equatable, Identifiable {
    let schemaVersion: Int
    let topic: String
    let runDate: String
    let runTime: String
    let status: String
    let headline: String
    let summary: String
    let items: [PulseNewsItem]
    let checkedSources: [ResearchNewsSource]

    var id: String {
        [topic, runDate, runTime].joined(separator: "-")
    }

    var displayDate: String {
        [runDate, runTime]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    var pairedItems: [PulseNewsItemPair] {
        stride(from: 0, to: items.count - 1, by: 2).map { index in
            PulseNewsItemPair(items: [items[index], items[index + 1]])
        }
    }
}

struct PulseNewsItem: Codable, Equatable, Hashable, Identifiable {
    let id: String
    let section: String
    let title: String
    let lead: String
    let whatHappened: String
    let keyFacts: [String]
    let reactions: [String]
    let whyItMatters: String
    let context: String
    let watchNext: [String]
    let sources: [ResearchNewsSource]
    let tags: [String]
    let priority: String
}

struct PulseNewsItemPair: Equatable, Hashable, Identifiable {
    let items: [PulseNewsItem]

    var id: String {
        items.map(\.id).joined(separator: "|")
    }
}
