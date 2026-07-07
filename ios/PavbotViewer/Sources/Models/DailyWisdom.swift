import Foundation

struct DailyWisdomEntry: Codable, Equatable, Identifiable {
    let text: String
    let attribution: String
    let context: String
    let reflection: String?
    let category: String

    init(
        text: String,
        attribution: String,
        context: String,
        reflection: String? = nil,
        category: String
    ) {
        self.text = text
        self.attribution = attribution
        self.context = context
        self.reflection = reflection
        self.category = category
    }

    var id: String {
        "\(text)|\(attribution)|\(context)|\(reflectionText)|\(category)"
    }

    var reflectionText: String {
        guard let reflection, !reflection.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return context
        }
        return reflection
    }
}

enum DailyWisdomProvider {
    static let resourceName = "daily-wisdom"

    static let fallbackEntry = DailyWisdomEntry(
        text: "Dzień zaczyna się od jednej dobrej decyzji.",
        attribution: "Sentencja kalendarzowa",
        context: "Wybierz najważniejszy krok i zrób go spokojnie.",
        reflection: "Największe porządki zaczynają się w jednej świadomej chwili. Kiedy wybierasz najważniejszy krok, dzień przestaje być chaosem i staje się przestrzenią, w której możesz zachować godność, rytm i wpływ.",
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

    static func rotatingEntry(
        for date: Date = Date(),
        entries inputEntries: [DailyWisdomEntry]? = nil,
        calendar inputCalendar: Calendar = .current,
        intervalSeconds: Int = 90
    ) -> DailyWisdomEntry {
        randomizedEntry(for: date, entries: inputEntries, calendar: inputCalendar, intervalSeconds: intervalSeconds)
    }

    static func randomizedEntry(
        for date: Date = Date(),
        entries inputEntries: [DailyWisdomEntry]? = nil,
        calendar inputCalendar: Calendar = .current,
        intervalSeconds: Int = 90
    ) -> DailyWisdomEntry {
        let entries = inputEntries ?? bundledEntries()
        guard !entries.isEmpty else { return fallbackEntry }

        let calendar = inputCalendar
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let year = components.year ?? 0
        let month = components.month ?? 0
        let day = components.day ?? 0
        let hour = components.hour ?? 0
        let minute = components.minute ?? 0
        let second = components.second ?? 0
        let stableDayKey = abs((year * 372) + (month * 31) + day)
        let secondsIntoDay = max(0, (hour * 3_600) + (minute * 60) + second)
        let slotsPerDay = max(1, 86_400 / max(1, intervalSeconds))
        let slot = (secondsIntoDay / max(1, intervalSeconds)) % slotsPerDay
        let dayOrdinal = calendar.ordinality(of: .day, in: .era, for: date) ?? stableDayKey
        let globalSlot = (dayOrdinal * slotsPerDay) + slot
        let seed = positiveModulo(mixedPositive(entries.count * 97), entries.count)
        let stride = coprimeStride(seed: seed + 397, count: entries.count)
        let randomizedIndex = positiveModulo(seed + (globalSlot * stride), entries.count)
        return entries[randomizedIndex]
    }

    private static func coprimeStride(seed: Int, count: Int) -> Int {
        guard count > 1 else { return 1 }
        var candidate = positiveModulo(seed, count - 1) + 1
        while greatestCommonDivisor(candidate, count) != 1 {
            candidate += 1
            if candidate >= count {
                candidate = 1
            }
        }
        return candidate
    }

    private static func mixedPositive(_ value: Int) -> Int {
        var result = UInt64(bitPattern: Int64(value))
        result &+= 0x9E3779B97F4A7C15
        result = (result ^ (result >> 30)) &* 0xBF58476D1CE4E5B9
        result = (result ^ (result >> 27)) &* 0x94D049BB133111EB
        result = result ^ (result >> 31)
        return Int(result & 0x7FFF_FFFF)
    }

    private static func positiveModulo(_ value: Int, _ divisor: Int) -> Int {
        let remainder = value % divisor
        return remainder >= 0 ? remainder : remainder + divisor
    }

    private static func greatestCommonDivisor(_ lhs: Int, _ rhs: Int) -> Int {
        var a = abs(lhs)
        var b = abs(rhs)
        while b != 0 {
            let next = a % b
            a = b
            b = next
        }
        return a
    }
}
