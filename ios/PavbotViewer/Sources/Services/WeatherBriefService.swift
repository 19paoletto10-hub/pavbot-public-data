import Foundation
import Observation

protocol WeatherBriefFetching {
    func fetchLatestReport(from serverURL: URL, location: WeatherBriefLocation?) async throws -> DailyWeatherReport
    func refreshReport(from serverURL: URL, location: WeatherBriefLocation?) async throws -> DailyWeatherReport
}

extension WeatherBriefFetching {
    func fetchLatestReport(from serverURL: URL) async throws -> DailyWeatherReport {
        try await fetchLatestReport(from: serverURL, location: nil)
    }

    func refreshReport(from serverURL: URL, location: WeatherBriefLocation?) async throws -> DailyWeatherReport {
        try await fetchLatestReport(from: serverURL, location: location)
    }
}

enum WeatherLocationMode: Equatable {
    case none
    case useIfAuthorized
    case requestIfNeeded
}

enum ManualWeatherLocationSettings {
    static let defaultsKey = "pavbot.manualWeatherLocation"

    static func location(defaults: UserDefaults = .standard) -> WeatherBriefLocation? {
        guard let data = defaults.data(forKey: defaultsKey) else { return nil }
        return try? JSONDecoder().decode(WeatherBriefLocation.self, from: data)
    }

    static func save(_ location: WeatherBriefLocation, defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(location) else { return }
        defaults.set(data, forKey: defaultsKey)
    }

    static func clear(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: defaultsKey)
    }
}

enum WeatherLocationPreference: Codable, Equatable {
    case defaultWroclaw
    case manual(WeatherBriefLocation)
    case currentDeviceLocation

    private enum CodingKeys: String, CodingKey {
        case mode
        case location
    }

    private enum Mode: String, Codable {
        case defaultWroclaw
        case manual
        case currentDeviceLocation
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let mode = try container.decode(Mode.self, forKey: .mode)
        switch mode {
        case .defaultWroclaw:
            self = .defaultWroclaw
        case .manual:
            self = .manual(try container.decode(WeatherBriefLocation.self, forKey: .location))
        case .currentDeviceLocation:
            self = .currentDeviceLocation
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .defaultWroclaw:
            try container.encode(Mode.defaultWroclaw, forKey: .mode)
        case .manual(let location):
            try container.encode(Mode.manual, forKey: .mode)
            try container.encode(location, forKey: .location)
        case .currentDeviceLocation:
            try container.encode(Mode.currentDeviceLocation, forKey: .mode)
        }
    }
}

enum WeatherLocationPreferenceSettings {
    static let defaultsKey = "pavbot.weatherLocationPreference"

    static func preference(defaults: UserDefaults = .standard) -> WeatherLocationPreference {
        if let data = defaults.data(forKey: defaultsKey),
           let preference = try? JSONDecoder().decode(WeatherLocationPreference.self, from: data) {
            return preference
        }

        if let legacyLocation = ManualWeatherLocationSettings.location(defaults: defaults) {
            return .manual(legacyLocation)
        }

        return .defaultWroclaw
    }

    static func save(_ preference: WeatherLocationPreference, defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(preference) else { return }
        defaults.set(data, forKey: defaultsKey)

        switch preference {
        case .manual(let location):
            ManualWeatherLocationSettings.save(location, defaults: defaults)
        case .defaultWroclaw, .currentDeviceLocation:
            ManualWeatherLocationSettings.clear(defaults: defaults)
        }
    }

    static func currentLocationLabel(
        defaults: UserDefaults = .standard,
        reportCity: String?
    ) -> String {
        switch preference(defaults: defaults) {
        case .defaultWroclaw:
            return WeatherBriefLocation.fallback.city
        case .manual(let location):
            return location.city
        case .currentDeviceLocation:
            if let reportCity, !reportCity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return "Bieżąca lokalizacja: \(reportCity)"
            }
            return "Bieżąca lokalizacja"
        }
    }
}

private enum WeatherBriefStoreError: LocalizedError, Equatable {
    case mismatchedLocation(expected: String, actual: String)

    var errorDescription: String? {
        switch self {
        case .mismatchedLocation(let expected, let actual):
            "Open-Meteo zwróciło raport dla lokalizacji \(actual), a wybrana lokalizacja to \(expected). Odśwież lokalizację i spróbuj ponownie."
        }
    }
}

@MainActor
@Observable
final class WeatherBriefStore {
    typealias LoadState = PavbotLoadState

    var report: DailyWeatherReport?
    var state: LoadState = .idle
    var cacheNotice: String?
    var locationNotice: String?
    var manualRefreshRetryAt: Date?
    var isRefreshing = false

    private let client: any WeatherBriefFetching
    private let cache: WeatherBriefCache
    private let cooldown: WeatherRefreshCooldown
    private let serverURLProvider: () -> URL?
    private let locationProvider: @MainActor (WeatherLocationMode) async throws -> WeatherBriefLocation?
    private let locationPreferenceProvider: () -> WeatherLocationPreference
    @ObservationIgnored private let reloadGate = ReloadGate()

    init(
        client: any WeatherBriefFetching = WeatherBriefClient(),
        cache: WeatherBriefCache = WeatherBriefCache(),
        cooldown: WeatherRefreshCooldown = WeatherRefreshCooldown(),
        serverURLProvider: @escaping () -> URL? = { WeatherBriefClient.openMeteoBaseURL },
        locationProvider: @MainActor @escaping (WeatherLocationMode) async throws -> WeatherBriefLocation? = { _ in nil },
        locationPreferenceProvider: @escaping () -> WeatherLocationPreference = { WeatherLocationPreferenceSettings.preference() }
    ) {
        self.client = client
        self.cache = cache
        self.cooldown = cooldown
        self.serverURLProvider = serverURLProvider
        self.locationProvider = locationProvider
        self.locationPreferenceProvider = locationPreferenceProvider
        self.report = cache.load()
        self.manualRefreshRetryAt = nil
        if report != nil {
            state = .loaded
        }
    }

    func load(minimumInterval: TimeInterval = 0) async {
        await loadSelectedLocation(minimumInterval: minimumInterval)
    }

    func loadSelectedLocation(minimumInterval: TimeInterval = 0) async {
        await loadLatest(minimumInterval: minimumInterval, locationMode: .none)
    }

    func loadWithCurrentLocation(minimumInterval: TimeInterval = 0) async {
        await loadLatest(minimumInterval: minimumInterval, locationMode: .useIfAuthorized)
    }

    func refreshSelectedLocation(minimumInterval: TimeInterval = 0) async {
        await refreshLatest(minimumInterval: minimumInterval, location: nil)
    }

    private func loadLatest(minimumInterval: TimeInterval = 0, locationMode: WeatherLocationMode) async {
        guard beginRequest(key: "weather.latest", minimumInterval: minimumInterval) else { return }
        defer { finishRequest(key: "weather.latest") }

        let serverURL = serverURLProvider() ?? WeatherBriefClient.openMeteoBaseURL

        if report == nil {
            state = .loading
        }
        let previousNotice = locationNotice
        var requestedLocation: WeatherBriefLocation?
        do {
            let location = await resolvedWeatherLocation(mode: locationMode)
            requestedLocation = location
            if let location {
                locationNotice = Self.loadingNotice(for: location)
            }
            let loadedReport = try await client.fetchLatestReport(from: serverURL, location: location)
            try Self.validate(loadedReport, matches: location)
            report = loadedReport
            cache.save(loadedReport)
            locationNotice = Self.successNotice(for: location, report: loadedReport, currentNotice: locationNotice)
            cacheNotice = nil
            state = .loaded
        } catch {
            handleWeatherLoadFailure(
                error,
                previousNotice: previousNotice,
                requestedLocation: requestedLocation,
                cachedMessage: PavbotCacheNoticeCopy.refreshFailed(context: "ostatni raport pogodowy")
            )
        }
    }

    func refreshNow(location: WeatherBriefLocation?) async {
        guard beginRequest(key: "weather.refresh") else { return }
        defer { finishRequest(key: "weather.refresh") }

        let serverURL = serverURLProvider() ?? WeatherBriefClient.openMeteoBaseURL

        if report == nil {
            state = .loading
        }
        let previousNotice = locationNotice
        var requestedLocation: WeatherBriefLocation?
        do {
            let resolvedLocation: WeatherBriefLocation?
            if let location {
                resolvedLocation = location
            } else {
                resolvedLocation = await resolvedWeatherLocation(mode: .none)
            }
            requestedLocation = resolvedLocation
            if let resolvedLocation {
                locationNotice = Self.loadingNotice(for: resolvedLocation)
            }
            let loadedReport = try await client.refreshReport(from: serverURL, location: resolvedLocation)
            try Self.validate(loadedReport, matches: resolvedLocation)
            report = loadedReport
            cache.save(loadedReport)
            locationNotice = Self.successNotice(for: resolvedLocation, report: loadedReport, currentNotice: locationNotice)
            manualRefreshRetryAt = nil
            cacheNotice = nil
            state = .loaded
        } catch {
            manualRefreshRetryAt = Self.manualRefreshRetryAt(from: error)
            handleWeatherLoadFailure(
                error,
                previousNotice: previousNotice,
                requestedLocation: requestedLocation,
                cachedMessage: PavbotCacheNoticeCopy.refreshFailed(context: "ostatni raport pogodowy")
            )
        }
    }

    private func refreshLatest(minimumInterval: TimeInterval = 0, location: WeatherBriefLocation?) async {
        guard beginRequest(key: "weather.refresh", minimumInterval: minimumInterval) else { return }
        defer { finishRequest(key: "weather.refresh") }

        let serverURL = serverURLProvider() ?? WeatherBriefClient.openMeteoBaseURL

        if report == nil {
            state = .loading
        }
        let previousNotice = locationNotice
        var requestedLocation: WeatherBriefLocation?
        do {
            let resolvedLocation: WeatherBriefLocation?
            if let location {
                resolvedLocation = location
            } else {
                resolvedLocation = await resolvedWeatherLocation(mode: .none)
            }
            requestedLocation = resolvedLocation
            if let resolvedLocation {
                locationNotice = Self.loadingNotice(for: resolvedLocation)
            }
            let loadedReport = try await client.refreshReport(from: serverURL, location: resolvedLocation)
            try Self.validate(loadedReport, matches: resolvedLocation)
            report = loadedReport
            cache.save(loadedReport)
            locationNotice = Self.successNotice(for: resolvedLocation, report: loadedReport, currentNotice: locationNotice)
            manualRefreshRetryAt = nil
            cacheNotice = nil
            state = .loaded
        } catch {
            manualRefreshRetryAt = Self.manualRefreshRetryAt(from: error)
            handleWeatherLoadFailure(
                error,
                previousNotice: previousNotice,
                requestedLocation: requestedLocation,
                cachedMessage: PavbotCacheNoticeCopy.refreshFailed(context: "ostatni raport pogodowy")
            )
        }
    }

    func activeManualRefreshRetryAt() -> Date? {
        if let retryAt = cooldown.activeRetryAt() {
            manualRefreshRetryAt = retryAt
            return retryAt
        }
        manualRefreshRetryAt = nil
        return nil
    }

    private static func timeLabel(_ value: Date) -> String {
        value.formatted(date: .omitted, time: .shortened)
    }

    private func resolvedWeatherLocation(mode: WeatherLocationMode) async -> WeatherBriefLocation? {
        if mode == .none {
            switch locationPreferenceProvider() {
            case .defaultWroclaw:
                locationNotice = Self.notice(for: .fallback)
                return nil
            case .manual(let manualLocation):
                locationNotice = Self.notice(for: manualLocation)
                return manualLocation
            case .currentDeviceLocation:
                return await currentDeviceLocation(mode: .useIfAuthorized)
            }
        }

        return await currentDeviceLocation(mode: mode)
    }

    private func currentDeviceLocation(mode: WeatherLocationMode) async -> WeatherBriefLocation? {
        do {
            let location = try await locationProvider(mode)
            locationNotice = Self.notice(for: location ?? .fallback)
            return location
        } catch {
            locationNotice = "Używam pogody dla Wrocławia. Lokalizacja jest niedostępna albo odmówiona."
            return nil
        }
    }

    private static func notice(for location: WeatherBriefLocation) -> String {
        if location.city == WeatherBriefLocation.fallback.city {
            return "Bieżąca prognoza dla: Wrocław."
        }
        return "Bieżąca prognoza dla: \(location.city)."
    }

    private static func notice(for location: WeatherBriefLocation?, report: DailyWeatherReport) -> String {
        if let location {
            return notice(for: location)
        }
        return "Bieżąca prognoza dla: \(report.city)."
    }

    private static func successNotice(
        for location: WeatherBriefLocation?,
        report: DailyWeatherReport,
        currentNotice: String?
    ) -> String {
        if location == nil, let currentNotice, currentNotice.hasPrefix("Używam pogody") {
            return currentNotice
        }
        return notice(for: location, report: report)
    }

    private static func loadingNotice(for location: WeatherBriefLocation) -> String {
        "Pobieram prognozę dla: \(location.city)..."
    }

    private static func validate(_ report: DailyWeatherReport, matches location: WeatherBriefLocation?) throws {
        guard let location else { return }
        guard city(report.city, matches: location.city) else {
            throw WeatherBriefStoreError.mismatchedLocation(expected: location.city, actual: report.city)
        }
    }

    private static func city(_ actual: String, matches expected: String) -> Bool {
        let actualFull = normalizedCity(actual)
        let expectedFull = normalizedCity(expected)
        guard !actualFull.isEmpty, !expectedFull.isEmpty else { return true }
        if actualFull == expectedFull { return true }

        let actualPrimary = normalizedCity(actual.components(separatedBy: ",").first ?? actual)
        let expectedPrimary = normalizedCity(expected.components(separatedBy: ",").first ?? expected)
        return !actualPrimary.isEmpty
            && !expectedPrimary.isEmpty
            && (actualPrimary == expectedPrimary
                || actualFull.contains(expectedPrimary)
                || expectedFull.contains(actualPrimary))
    }

    private static func normalizedCity(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "pl_PL"))
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func handleWeatherLoadFailure(
        _ error: Error,
        previousNotice: String?,
        requestedLocation: WeatherBriefLocation?,
        cachedMessage: String
    ) {
        locationNotice = previousNotice
        let userError = Self.userFacingError(for: error, requestedLocation: requestedLocation)
        if report != nil {
            if error is WeatherBriefStoreError {
                cacheNotice = userError.message
            } else {
                cacheNotice = cachedMessage
            }
            state = .loaded
        } else {
            cacheNotice = nil
            state = .failed(userError)
        }
    }

    private static func userFacingError(
        for error: Error,
        requestedLocation: WeatherBriefLocation?
    ) -> PavbotUserFacingError {
        if let mismatch = error as? WeatherBriefStoreError {
            switch mismatch {
            case .mismatchedLocation:
                return .custom(
                    title: "Nie udało się pobrać prognozy dla tej lokalizacji",
                    message: mismatch.localizedDescription,
                    actionTitle: "Odśwież ponownie",
                    systemImage: "location.slash.fill",
                    tint: .orange
                )
            }
        }

        if let requestedLocation {
            return .custom(
                title: "Nie udało się pobrać prognozy dla \(requestedLocation.city)",
                message: "Sprawdź połączenie z Open-Meteo i spróbuj ponownie. Szczegóły: \(error.localizedDescription)",
                actionTitle: "Spróbuj ponownie",
                systemImage: "cloud.sun.fill",
                tint: .blue
            )
        }

        return .network(error, context: .weather)
    }

    private static func manualRefreshRetryAt(from error: Error) -> Date? {
        if let clientError = error as? WeatherBriefClient.ClientError,
           case .refreshLocked(let retryAt) = clientError {
            return retryAt
        }
        return nil
    }

    private func beginRequest(key: String, minimumInterval: TimeInterval = 0) -> Bool {
        guard reloadGate.begin(key: key, minimumInterval: minimumInterval) else { return false }
        isRefreshing = true
        return true
    }

    private func finishRequest(key: String) {
        reloadGate.finish(key: key)
        isRefreshing = false
    }
}

struct WeatherRefreshCooldown {
    private let defaults: UserDefaults
    private let key: String
    private var calendar: Calendar
    private let nowProvider: () -> Date

    init(
        defaults: UserDefaults = .standard,
        key: String = "pavbot.weatherManualRefreshRetryAt",
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init
    ) {
        self.defaults = defaults
        self.key = key
        self.calendar = calendar
        self.nowProvider = now
    }

    func activeRetryAt() -> Date? {
        activeRetryAt(at: nowProvider())
    }

    func activeRetryAt(at now: Date) -> Date? {
        guard let retryAt = retryAt(), retryAt > now else { return nil }
        return retryAt
    }

    @discardableResult
    func recordRefresh(at value: Date? = nil) -> Date {
        let retryAt = nextHour(after: value ?? nowProvider())
        setRetryAt(retryAt)
        return retryAt
    }

    func setRetryAt(_ value: Date) {
        defaults.set(value, forKey: key)
    }

    func retryAt() -> Date? {
        defaults.object(forKey: key) as? Date
    }

    private func nextHour(after value: Date) -> Date {
        if let interval = calendar.dateInterval(of: .hour, for: value) {
            return interval.end
        }
        return calendar.date(byAdding: .hour, value: 1, to: value) ?? value.addingTimeInterval(3600)
    }
}

struct WeatherBriefClient: WeatherBriefFetching {
    static let openMeteoBaseURL = URL(string: "https://api.open-meteo.com")!

    enum ClientError: LocalizedError {
        case invalidResponse
        case httpStatus(Int)
        case refreshLocked(Date?)

        var errorDescription: String? {
            switch self {
            case .invalidResponse:
                "Open-Meteo zwróciło nieprawidłową odpowiedź."
            case .httpStatus(let status):
                "Open-Meteo zwróciło HTTP \(status)."
            case .refreshLocked(let retryAt):
                if let retryAt {
                    "Raport pogodowy można odświeżyć ponownie po \(retryAt.formatted(date: .omitted, time: .shortened))."
                } else {
                    "Raport pogodowy można odświeżyć ponownie w następnej godzinie."
                }
            }
        }
    }

    private struct RefreshLockedResponse: Decodable {
        struct Detail: Decodable {
            let retryAt: String?
        }

        let detail: Detail?
    }

    var session: URLSession = .shared
    var decoder: JSONDecoder = .pavbot

    func fetchLatestReport(from serverURL: URL, location: WeatherBriefLocation?) async throws -> DailyWeatherReport {
        try await send(forecastRequest(for: location, forceRefresh: false), location: location)
    }

    func refreshReport(from serverURL: URL, location: WeatherBriefLocation?) async throws -> DailyWeatherReport {
        try await send(forecastRequest(for: location, forceRefresh: true), location: location)
    }

    func forecastRequest(for location: WeatherBriefLocation?, forceRefresh: Bool) throws -> URLRequest {
        let resolvedLocation = location ?? .fallback
        let endpoint = Self.openMeteoBaseURL
            .appendingPathComponent("v1")
            .appendingPathComponent("forecast")
        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            throw ClientError.invalidResponse
        }
        components.queryItems = [
            URLQueryItem(name: "latitude", value: Self.coordinateString(resolvedLocation.latitude)),
            URLQueryItem(name: "longitude", value: Self.coordinateString(resolvedLocation.longitude)),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "current", value: [
                "temperature_2m",
                "apparent_temperature",
                "relative_humidity_2m",
                "weather_code",
                "wind_speed_10m"
            ].joined(separator: ",")),
            URLQueryItem(name: "hourly", value: [
                "temperature_2m",
                "precipitation_probability",
                "precipitation",
                "rain",
                "showers",
                "snowfall"
            ].joined(separator: ",")),
            URLQueryItem(name: "daily", value: [
                "weather_code",
                "temperature_2m_max",
                "temperature_2m_min",
                "sunrise",
                "sunset",
                "precipitation_sum",
                "precipitation_probability_max"
            ].joined(separator: ","))
        ]
        guard let url = components.url else {
            throw ClientError.invalidResponse
        }

        var request = URLRequest(
            url: url,
            cachePolicy: forceRefresh ? .reloadIgnoringLocalAndRemoteCacheData : .reloadIgnoringLocalAndRemoteCacheData
        )
        request.httpMethod = "GET"
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue("no-cache", forHTTPHeaderField: "Pragma")
        request.timeoutInterval = 12
        return request
    }

    private func send(_ request: URLRequest, location: WeatherBriefLocation?) async throws -> DailyWeatherReport {
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClientError.invalidResponse
        }
        if httpResponse.statusCode == 429 {
            let locked = try? decoder.decode(RefreshLockedResponse.self, from: data)
            let retryAt = locked?.detail?.retryAt.flatMap(ISO8601DateFormatter.pavbotDate(from:))
            throw ClientError.refreshLocked(retryAt)
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw ClientError.httpStatus(httpResponse.statusCode)
        }
        let forecast = try decoder.decode(OpenMeteoForecastResponse.self, from: data)
        return try forecast.dailyWeatherReport(location: location ?? .fallback)
    }

    private static func coordinateString(_ value: Double) -> String {
        let text = String(format: "%.6f", value)
        return text
            .replacingOccurrences(of: #"0+$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\.$"#, with: "", options: .regularExpression)
    }
}

private struct OpenMeteoForecastResponse: Decodable {
    let current: Current?
    let currentUnits: CurrentUnits?
    let hourly: Hourly?
    let hourlyUnits: HourlyUnits?
    let daily: Daily?
    let dailyUnits: DailyUnits?

    enum CodingKeys: String, CodingKey {
        case current
        case currentUnits = "current_units"
        case hourly
        case hourlyUnits = "hourly_units"
        case daily
        case dailyUnits = "daily_units"
    }

    struct Current: Decodable {
        let time: String?
        let temperature: Double?
        let apparentTemperature: Double?
        let relativeHumidity: Int?
        let weatherCode: Int?
        let windSpeed: Double?

        enum CodingKeys: String, CodingKey {
            case time
            case temperature = "temperature_2m"
            case apparentTemperature = "apparent_temperature"
            case relativeHumidity = "relative_humidity_2m"
            case weatherCode = "weather_code"
            case windSpeed = "wind_speed_10m"
        }
    }

    struct CurrentUnits: Decodable {
        let temperature: String?
        let windSpeed: String?

        enum CodingKeys: String, CodingKey {
            case temperature = "temperature_2m"
            case windSpeed = "wind_speed_10m"
        }
    }

    struct Hourly: Decodable {
        let time: [String]
        let temperature: [Double]
        let precipitationProbability: [Int]?
        let precipitation: [Double]?
        let rain: [Double]?
        let showers: [Double]?
        let snowfall: [Double]?

        enum CodingKeys: String, CodingKey {
            case time
            case temperature = "temperature_2m"
            case precipitationProbability = "precipitation_probability"
            case precipitation
            case rain
            case showers
            case snowfall
        }
    }

    struct HourlyUnits: Decodable {
        let temperature: String?
        let precipitation: String?

        enum CodingKeys: String, CodingKey {
            case temperature = "temperature_2m"
            case precipitation
        }
    }

    struct Daily: Decodable {
        let time: [String]
        let weatherCode: [Int]?
        let temperatureMax: [Double]?
        let temperatureMin: [Double]?
        let sunrise: [String]?
        let sunset: [String]?
        let precipitationSum: [Double]?
        let precipitationProbabilityMax: [Int]?

        enum CodingKeys: String, CodingKey {
            case time
            case weatherCode = "weather_code"
            case temperatureMax = "temperature_2m_max"
            case temperatureMin = "temperature_2m_min"
            case sunrise
            case sunset
            case precipitationSum = "precipitation_sum"
            case precipitationProbabilityMax = "precipitation_probability_max"
        }
    }

    struct DailyUnits: Decodable {
        let temperatureMax: String?
        let precipitationSum: String?

        enum CodingKeys: String, CodingKey {
            case temperatureMax = "temperature_2m_max"
            case precipitationSum = "precipitation_sum"
        }
    }

    func dailyWeatherReport(location: WeatherBriefLocation) throws -> DailyWeatherReport {
        guard let day = daily?.time.first else {
            throw WeatherBriefClient.ClientError.invalidResponse
        }
        let weatherCode = current?.weatherCode ?? daily?.weatherCode?.first ?? 0
        let condition = Self.conditionLabel(for: weatherCode)
        let temperatureUnit = currentUnits?.temperature ?? dailyUnits?.temperatureMax ?? "°C"
        let precipitationUnit = dailyUnits?.precipitationSum ?? hourlyUnits?.precipitation ?? "mm"
        let windUnit = currentUnits?.windSpeed ?? "km/h"
        let generatedAt = ISO8601DateFormatter().string(from: Date())
        let currentTemperature = current?.temperature
        let minTemperature = daily?.temperatureMin?.first
        let maxTemperature = daily?.temperatureMax?.first
        let precipitationProbability = daily?.precipitationProbabilityMax?.first ?? hourly?.precipitationProbability?.max() ?? 0
        let precipitationTotal = daily?.precipitationSum?.first

        return DailyWeatherReport(
            id: "\(Self.slug(location.city))-\(day)",
            city: location.city,
            date: day,
            weekday: Self.weekday(for: day),
            generatedAt: generatedAt,
            nameDays: [],
            headline: "\(location.city): \(condition.lowercased()) i \(Self.temperatureText(currentTemperature, unit: temperatureUnit))",
            summary: "\(Self.weekday(for: day).capitalized), \(day). \(condition). Dane z Open-Meteo dla lokalizacji \(location.city).",
            recommendation: Self.recommendation(probability: precipitationProbability),
            temperature: DailyWeatherTemperature(
                current: currentTemperature,
                apparent: current?.apparentTemperature,
                min: minTemperature,
                max: maxTemperature,
                unit: temperatureUnit
            ),
            conditions: DailyWeatherConditions(code: weatherCode, label: condition),
            precipitation: DailyWeatherPrecipitation(
                probability: precipitationProbability,
                total: precipitationTotal,
                unit: precipitationUnit
            ),
            wind: DailyWeatherWind(speed: current?.windSpeed, unit: windUnit),
            humidity: current?.relativeHumidity ?? 0,
            sunrise: daily?.sunrise?.first,
            sunset: daily?.sunset?.first,
            source: "Open-Meteo Forecast API",
            hourlyTemperature: hourlyTemperature(unit: temperatureUnit),
            temperatureTimeline: hourlyTemperature(unit: temperatureUnit),
            hourlyPrecipitation: hourlyPrecipitation(unit: precipitationUnit),
            precipitationTimeline: hourlyPrecipitation(unit: precipitationUnit)
        )
    }

    private func hourlyTemperature(unit: String) -> [DailyWeatherHourlyTemperature] {
        guard let hourly else { return [] }
        return hourly.time.enumerated().compactMap { index, time in
            guard index < hourly.temperature.count else { return nil }
            return DailyWeatherHourlyTemperature(time: time, temperature: hourly.temperature[index], unit: unit)
        }
    }

    private func hourlyPrecipitation(unit: String) -> [DailyWeatherHourlyPrecipitation] {
        guard let hourly else { return [] }
        return hourly.time.enumerated().map { index, time in
            let probability = hourly.precipitationProbability?[safe: index] ?? 0
            let amount = hourly.precipitation?[safe: index] ?? 0
            let rain = hourly.rain?[safe: index] ?? 0
            let showers = hourly.showers?[safe: index] ?? 0
            let snowfall = hourly.snowfall?[safe: index] ?? 0
            return DailyWeatherHourlyPrecipitation(
                time: time,
                probability: probability,
                amount: amount,
                rain: rain,
                showers: showers,
                snowfall: snowfall,
                kind: Self.precipitationKind(rain: rain, showers: showers, snowfall: snowfall, probability: probability),
                unit: unit
            )
        }
    }

    private static func conditionLabel(for code: Int) -> String {
        switch code {
        case 0: "Bezchmurnie"
        case 1: "Głównie bezchmurnie"
        case 2: "Częściowe zachmurzenie"
        case 3: "Pochmurno"
        case 45, 48: "Mgła"
        case 51, 53, 55: "Mżawka"
        case 61, 63, 65: "Deszcz"
        case 66, 67: "Marznący deszcz"
        case 71, 73, 75, 77: "Śnieg"
        case 80, 81, 82: "Przelotne opady"
        case 85, 86: "Przelotny śnieg"
        case 95, 96, 99: "Burza"
        default: "Warunki zmienne"
        }
    }

    private static func precipitationKind(
        rain: Double,
        showers: Double,
        snowfall: Double,
        probability: Int
    ) -> WeatherPrecipitationKind {
        if snowfall > 0, rain > 0 || showers > 0 { return .mixed }
        if snowfall > 0 { return .snow }
        if rain > 0 || showers > 0 { return .rain }
        return probability >= 20 ? .possible : .possible
    }

    private static func recommendation(probability: Int) -> String {
        probability >= 40
            ? "Na dziś: miej pod ręką parasol albo kurtkę przeciwdeszczową."
            : "Na dziś: dzień powinien obyć się bez większych opadów."
    }

    private static func weekday(for day: String) -> String {
        guard let date = DateFormatter.pavbotDay.date(from: day) else { return day }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "pl_PL")
        formatter.dateFormat = "EEEE"
        return formatter.string(from: date)
    }

    private static func temperatureText(_ value: Double?, unit: String) -> String {
        guard let value else { return "--\(unit)" }
        return value.rounded() == value ? "\(Int(value))\(unit)" : String(format: "%.1f%@", value, unit)
    }

    private static func slug(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "pl_PL"))
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

struct WeatherBriefCache {
    private let defaults: UserDefaults
    private let key = "pavbot.cachedDailyWeatherReport"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> DailyWeatherReport? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder.pavbot.decode(DailyWeatherReport.self, from: data)
    }

    func save(_ report: DailyWeatherReport) {
        guard let data = try? JSONEncoder().encode(report) else { return }
        defaults.set(data, forKey: key)
    }
}

enum DailyWeatherNotificationSettings {
    static let enabledDefaultsKey = "pavbot.dailyWeatherNotificationsEnabled"

    static func isEnabled(defaults: UserDefaults = .standard) -> Bool {
        if defaults.object(forKey: enabledDefaultsKey) == nil {
            return true
        }
        return defaults.bool(forKey: enabledDefaultsKey)
    }

    static func setEnabled(_ enabled: Bool, defaults: UserDefaults = .standard) {
        defaults.set(enabled, forKey: enabledDefaultsKey)
    }
}
