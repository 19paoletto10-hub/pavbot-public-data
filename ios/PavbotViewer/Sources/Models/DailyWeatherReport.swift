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
        temperatureTimeline: [DailyWeatherHourlyTemperature] = []
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
