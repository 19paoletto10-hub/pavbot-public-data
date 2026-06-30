import Foundation

struct DailyWisdomEntry: Codable, Equatable, Identifiable {
    let text: String
    let attribution: String
    let context: String
    let category: String

    var id: String {
        "\(text)|\(attribution)|\(context)|\(category)"
    }
}

enum DailyWisdomProvider {
    static let resourceName = "daily-wisdom"

    static let fallbackEntry = DailyWisdomEntry(
        text: "Dzień zaczyna się od jednej dobrej decyzji.",
        attribution: "Sentencja kalendarzowa",
        context: "Wybierz najważniejszy krok i zrób go spokojnie.",
        category: "spokój"
    )

    static func bundledEntries(bundle: Bundle = Bundle.main) -> [DailyWisdomEntry] {
        guard let url = bundle.url(forResource: resourceName, withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let entries = try? decodeEntries(from: data),
              !entries.isEmpty
        else {
            return [fallbackEntry]
        }
        return entries
    }

    static func decodeEntries(from data: Data) throws -> [DailyWisdomEntry] {
        try JSONDecoder.pavbot.decode([DailyWisdomEntry].self, from: data)
    }

    static func entry(
        for date: Date = Date(),
        entries inputEntries: [DailyWisdomEntry]? = nil,
        calendar inputCalendar: Calendar = .current
    ) -> DailyWisdomEntry {
        let entries = inputEntries ?? bundledEntries()
        guard !entries.isEmpty else { return fallbackEntry }

        let calendar = inputCalendar
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let year = components.year ?? 0
        let month = components.month ?? 0
        let day = components.day ?? 0
        let stableDayKey = abs((year * 372) + (month * 31) + day)
        return entries[stableDayKey % entries.count]
    }
}
