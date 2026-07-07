import Foundation

struct DailyWeatherReport: Codable, Equatable, Identifiable {
    let id: String
    let city: String
    let date: String
    let weekday: String
    let generatedAt: String
    let nameDays: [String]
    let headline: String
    let summary: String
    let recommendation: String
    let temperature: DailyWeatherTemperature
    let conditions: DailyWeatherConditions
    let precipitation: DailyWeatherPrecipitation
    let wind: DailyWeatherWind
    let humidity: Int
    let sunrise: String?
    let sunset: String?
    let source: String
    let hourlyTemperature: [DailyWeatherHourlyTemperature]
    let temperatureTimeline: [DailyWeatherHourlyTemperature]
    let hourlyPrecipitation: [DailyWeatherHourlyPrecipitation]
    let precipitationTimeline: [DailyWeatherHourlyPrecipitation]

    init(
        id: String,
        city: String,
        date: String,
        weekday: String,
        generatedAt: String,
        nameDays: [String],
        headline: String,
        summary: String,
        recommendation: String,
        temperature: DailyWeatherTemperature,
        conditions: DailyWeatherConditions,
        precipitation: DailyWeatherPrecipitation,
        wind: DailyWeatherWind,
        humidity: Int,
        sunrise: String?,
        sunset: String?,
        source: String,
        hourlyTemperature: [DailyWeatherHourlyTemperature] = [],
        temperatureTimeline: [DailyWeatherHourlyTemperature] = [],
        hourlyPrecipitation: [DailyWeatherHourlyPrecipitation] = [],
        precipitationTimeline: [DailyWeatherHourlyPrecipitation] = []
    ) {
        self.id = id
        self.city = city
        self.date = date
        self.weekday = weekday
        self.generatedAt = generatedAt
        self.nameDays = nameDays
        self.headline = headline
        self.summary = summary
        self.recommendation = recommendation
        self.temperature = temperature
        self.conditions = conditions
        self.precipitation = precipitation
        self.wind = wind
        self.humidity = humidity
        self.sunrise = sunrise
        self.sunset = sunset
        self.source = source
        self.hourlyTemperature = hourlyTemperature
        self.temperatureTimeline = temperatureTimeline
        self.hourlyPrecipitation = hourlyPrecipitation
        self.precipitationTimeline = precipitationTimeline
    }

    enum CodingKeys: String, CodingKey {
        case id
        case city
        case date
        case weekday
        case generatedAt
        case nameDays
        case headline
        case summary
        case recommendation
        case temperature
        case conditions
        case precipitation
        case wind
        case humidity
        case sunrise
        case sunset
        case source
        case hourlyTemperature
        case temperatureTimeline
        case hourlyPrecipitation
        case precipitationTimeline
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        city = try container.decode(String.self, forKey: .city)
        date = try container.decode(String.self, forKey: .date)
        weekday = try container.decode(String.self, forKey: .weekday)
        generatedAt = try container.decode(String.self, forKey: .generatedAt)
        nameDays = try container.decode([String].self, forKey: .nameDays)
        headline = try container.decode(String.self, forKey: .headline)
        summary = try container.decode(String.self, forKey: .summary)
        recommendation = try container.decode(String.self, forKey: .recommendation)
        temperature = try container.decode(DailyWeatherTemperature.self, forKey: .temperature)
        conditions = try container.decode(DailyWeatherConditions.self, forKey: .conditions)
        precipitation = try container.decode(DailyWeatherPrecipitation.self, forKey: .precipitation)
        wind = try container.decode(DailyWeatherWind.self, forKey: .wind)
        humidity = try container.decode(Int.self, forKey: .humidity)
        sunrise = try container.decodeIfPresent(String.self, forKey: .sunrise)
        sunset = try container.decodeIfPresent(String.self, forKey: .sunset)
        source = try container.decode(String.self, forKey: .source)
        hourlyTemperature = try container.decodeIfPresent([DailyWeatherHourlyTemperature].self, forKey: .hourlyTemperature) ?? []
        temperatureTimeline = try container.decodeIfPresent([DailyWeatherHourlyTemperature].self, forKey: .temperatureTimeline) ?? []
        hourlyPrecipitation = try container.decodeIfPresent([DailyWeatherHourlyPrecipitation].self, forKey: .hourlyPrecipitation) ?? []
        precipitationTimeline = try container.decodeIfPresent([DailyWeatherHourlyPrecipitation].self, forKey: .precipitationTimeline) ?? []
    }

    var nameDaysLabel: String {
        nameDays.joined(separator: ", ")
    }

    var displayDate: String {
        guard let dateValue = DateFormatter.pavbotDay.date(from: date) else {
            return date
        }
        return DateFormatter.polishLongDate.string(from: dateValue)
    }

    var generatedAtDate: Date? {
        ISO8601DateFormatter.pavbotDate(from: generatedAt)
    }

    func timelineTemperaturePoints(
        startingAt now: Date = Date(),
        calendar inputCalendar: Calendar = .current
    ) -> [DailyWeatherHourlyTemperature] {
        if !temperatureTimeline.isEmpty {
            return temperatureTimeline
        }

        let currentDay = DateFormatter.pavbotDay.string(from: now)
        guard currentDay == date else {
            return hourlyTemperature
        }

        var calendar = inputCalendar
        calendar.timeZone = DateFormatter.pavbotWeatherHour.timeZone ?? .current
        let currentHour = calendar.dateInterval(of: .hour, for: now)?.start ?? now
        let filtered = hourlyTemperature.filter { item in
            guard item.time.hasPrefix(date), let dateValue = item.dateValue else { return false }
            return dateValue >= currentHour
        }
        return filtered.isEmpty ? hourlyTemperature : filtered
    }

    func timelinePrecipitationPoints(
        startingAt now: Date = Date(),
        calendar inputCalendar: Calendar = .current
    ) -> [DailyWeatherHourlyPrecipitation] {
        if !precipitationTimeline.isEmpty {
            return precipitationTimeline
        }

        let currentDay = DateFormatter.pavbotDay.string(from: now)
        guard currentDay == date else {
            return hourlyPrecipitation
        }

        var calendar = inputCalendar
        calendar.timeZone = DateFormatter.pavbotWeatherHour.timeZone ?? .current
        let currentHour = calendar.dateInterval(of: .hour, for: now)?.start ?? now
        let filtered = hourlyPrecipitation.filter { item in
            guard item.time.hasPrefix(date), let dateValue = item.dateValue else { return false }
            return dateValue >= currentHour
        }
        return filtered.isEmpty ? hourlyPrecipitation : filtered
    }

    var weatherNarrativeRecommendation: String {
        let precipitation = WeatherPrecipitationTilePresentation(report: self)
        guard precipitation.hasHourlyData else {
            return recommendation
        }
        guard !recommendation.containsPrecipitationHourWindow else {
            return recommendation
        }
        return precipitation.advice
    }
}

struct DailyWeatherHourlyTemperature: Codable, Equatable, Identifiable {
    let time: String
    let temperature: Double
    let unit: String

    var id: String { time }

    var dateValue: Date? {
        DateFormatter.pavbotWeatherHour.date(from: time)
    }

    var hourLabel: String {
        if let time = time.split(separator: "T").last {
            return String(time.prefix(5))
        }
        return time
    }

    var displayTemperature: String {
        if temperature.rounded() == temperature {
            return "\(Int(temperature))\(unit)"
        }
        return String(format: "%.1f%@", temperature, unit)
    }
}

struct DailyWeatherHourlyPrecipitation: Codable, Equatable, Identifiable {
    let time: String
    let probability: Int
    let amount: Double
    let rain: Double
    let showers: Double
    let snowfall: Double
    let kind: WeatherPrecipitationKind
    let unit: String

    var id: String { time }

    var dateValue: Date? {
        DateFormatter.pavbotWeatherHour.date(from: time)
    }

    var hourLabel: String {
        if let time = time.split(separator: "T").last {
            return String(time.prefix(5))
        }
        return time
    }

    var isSignificant: Bool {
        probability >= 20 || amount > 0
    }

    var amountLabel: String {
        if amount.rounded() == amount {
            return "\(Int(amount)) \(unit)"
        }
        return String(format: "%.1f %@", amount, unit)
    }
}

enum WeatherPrecipitationKind: String, Codable, Equatable {
    case rain
    case snow
    case mixed
    case possible

    var polishGenitiveLabel: String {
        switch self {
        case .rain:
            "deszczu"
        case .snow:
            "śniegu"
        case .mixed:
            "deszczu ze śniegiem"
        case .possible:
            "opadów"
        }
    }

    var practicalAdvice: String {
        switch self {
        case .rain:
            "weź parasol lub lekką kurtkę przeciwdeszczową"
        case .snow:
            "uważaj na śliskie chodniki i zaplanuj wolniejsze wyjście"
        case .mixed:
            "weź coś przeciwdeszczowego i uważaj na śliskie miejsca"
        case .possible:
            "miej pod ręką parasol, jeśli wychodzisz na dłużej"
        }
    }
}

struct WeatherPrecipitationTilePresentation: Equatable {
    let city: String
    let dailyProbabilityLabel: String
    let dailyTotalLabel: String
    let timeline: [DailyWeatherHourlyPrecipitation]

    init(
        report: DailyWeatherReport,
        now: Date = Date(),
        calendar: Calendar = .current
    ) {
        city = report.city
        dailyProbabilityLabel = report.precipitation.probabilityLabel
        dailyTotalLabel = report.precipitation.totalLabel
        timeline = report.timelinePrecipitationPoints(startingAt: now, calendar: calendar)
    }

    var significantPoints: [DailyWeatherHourlyPrecipitation] {
        timeline.filter(\.isSignificant)
    }

    var measurablePoints: [DailyWeatherHourlyPrecipitation] {
        timeline.filter { point in
            point.amount > 0 || point.rain > 0 || point.showers > 0 || point.snowfall > 0
        }
    }

    var hasHourlyData: Bool {
        !timeline.isEmpty
    }

    var chartPoints: [DailyWeatherHourlyPrecipitation] {
        significantPoints
    }

    var advice: String {
        guard hasHourlyData else {
            return "Dzisiaj ryzyko opadów wynosi \(dailyProbabilityLabel), ale brak godzinowego rozkładu dla tej lokalizacji."
        }
        guard !significantPoints.isEmpty else {
            return "Do końca dnia nie widać istotnych opadów dla \(city); parasol raczej nie będzie potrzebny."
        }

        let advicePoints = measurablePoints.isEmpty ? significantPoints : measurablePoints
        let kind = dominantKind(in: advicePoints)
        let timeText = timeWindowsText(for: advicePoints)
        if measurablePoints.isEmpty || kind == .possible {
            return "Ryzyko opadów widać \(timeText), więc \(kind.practicalAdvice)."
        }
        return "Opadów \(kind.polishGenitiveLabel) spodziewaj się \(timeText), więc \(kind.practicalAdvice)."
    }

    private func dominantKind(in points: [DailyWeatherHourlyPrecipitation]) -> WeatherPrecipitationKind {
        if points.contains(where: { $0.kind == .mixed }) {
            return .mixed
        }
        if points.contains(where: { $0.kind == .snow }) {
            return .snow
        }
        if points.contains(where: { $0.kind == .rain }) {
            return .rain
        }
        return .possible
    }

    private func timeWindowsText(for points: [DailyWeatherHourlyPrecipitation]) -> String {
        let windows = groupedWindows(for: points).map { window in
            window.start.id == window.end.id ? window.start.hourLabel : "\(window.start.hourLabel)-\(window.end.hourLabel)"
        }
        return "około \(joinPolish(windows))"
    }

    private func groupedWindows(
        for points: [DailyWeatherHourlyPrecipitation]
    ) -> [(start: DailyWeatherHourlyPrecipitation, end: DailyWeatherHourlyPrecipitation)] {
        let sortedPoints = points.sorted { first, second in
            switch (first.dateValue, second.dateValue) {
            case let (.some(firstDate), .some(secondDate)):
                return firstDate < secondDate
            default:
                return first.time < second.time
            }
        }
        guard var currentStart = sortedPoints.first, var currentEnd = sortedPoints.first else {
            return []
        }

        var windows: [(start: DailyWeatherHourlyPrecipitation, end: DailyWeatherHourlyPrecipitation)] = []
        for point in sortedPoints.dropFirst() {
            if areAdjacentHours(currentEnd, point) {
                currentEnd = point
            } else {
                windows.append((start: currentStart, end: currentEnd))
                currentStart = point
                currentEnd = point
            }
        }
        windows.append((start: currentStart, end: currentEnd))
        return windows
    }

    private func areAdjacentHours(
        _ first: DailyWeatherHourlyPrecipitation,
        _ second: DailyWeatherHourlyPrecipitation
    ) -> Bool {
        guard let firstDate = first.dateValue, let secondDate = second.dateValue else {
            return false
        }
        return secondDate.timeIntervalSince(firstDate) <= 3_900
    }

    private func joinPolish(_ items: [String]) -> String {
        switch items.count {
        case 0:
            return ""
        case 1:
            return items[0]
        case 2:
            return "\(items[0]) i \(items[1])"
        default:
            return "\(items.dropLast().joined(separator: ", ")) i \(items.last ?? "")"
        }
    }
}

struct WeatherBriefLocation: Codable, Equatable {
    let latitude: Double
    let longitude: Double
    let city: String

    static let fallback = WeatherBriefLocation(
        latitude: 51.1079,
        longitude: 17.0385,
        city: "Wrocław"
    )
}

enum WeatherRangeTileMode: Equatable {
    case value
    case chart

    mutating func toggle() {
        self = self == .value ? .chart : .value
    }
}

enum WeatherPrecipitationTileMode: Equatable {
    case value
    case chart

    mutating func toggle() {
        self = self == .value ? .chart : .value
    }
}

private extension String {
    var containsPrecipitationHourWindow: Bool {
        guard range(
            of: #"(?<!\d)\d{1,2}:\d{2}\s*(?:-\s*\d{1,2}:\d{2})?(?!\d)"#,
            options: .regularExpression
        ) != nil else {
            return false
        }

        let text = lowercased()
        return [
            "deszcz",
            "mżawk",
            "opad",
            "parasol",
            "śnieg",
            "ulew"
        ].contains { text.contains($0) }
    }
}

struct DailyWeatherTemperature: Codable, Equatable {
    let current: Double?
    let apparent: Double?
    let min: Double?
    let max: Double?
    let unit: String

    var currentLabel: String {
        temperatureLabel(current)
    }

    var rangeLabel: String {
        "\(temperatureLabel(min)) / \(temperatureLabel(max))"
    }

    var apparentLabel: String {
        temperatureLabel(apparent)
    }

    private func temperatureLabel(_ value: Double?) -> String {
        guard let value else { return "--\(unit)" }
        if value.rounded() == value {
            return "\(Int(value))\(unit)"
        }
        return String(format: "%.1f%@", value, unit)
    }
}

struct DailyWeatherConditions: Codable, Equatable {
    let code: Int
    let label: String
}

struct DailyWeatherPrecipitation: Codable, Equatable {
    let probability: Int
    let total: Double?
    let unit: String

    var probabilityLabel: String {
        "\(probability)%"
    }

    var totalLabel: String {
        guard let total else { return "-- \(unit)" }
        if total.rounded() == total {
            return "\(Int(total)) \(unit)"
        }
        return String(format: "%.1f %@", total, unit)
    }
}

struct DailyWeatherWind: Codable, Equatable {
    let speed: Double?
    let unit: String

    var speedLabel: String {
        guard let speed else { return "-- \(unit)" }
        if speed.rounded() == speed {
            return "\(Int(speed)) \(unit)"
        }
        return String(format: "%.1f %@", speed, unit)
    }
}

extension DateFormatter {
    static let polishLongDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "pl_PL")
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        return formatter
    }()

    static let pavbotWeatherHour: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        return formatter
    }()
}
