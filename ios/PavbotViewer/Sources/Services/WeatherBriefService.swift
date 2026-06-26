import Foundation
import Observation

protocol WeatherBriefFetching {
    func fetchLatestReport(from serverURL: URL, location: WeatherBriefLocation?) async throws -> DailyWeatherReport
}

extension WeatherBriefFetching {
    func fetchLatestReport(from serverURL: URL) async throws -> DailyWeatherReport {
        try await fetchLatestReport(from: serverURL, location: nil)
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
    private let locationProvider: @MainActor () async throws -> WeatherBriefLocation?
    @ObservationIgnored private let reloadGate = ReloadGate()

    init(
        client: any WeatherBriefFetching = WeatherBriefClient(),
        cache: WeatherBriefCache = WeatherBriefCache(),
        cooldown: WeatherRefreshCooldown = WeatherRefreshCooldown(),
        serverURLProvider: @escaping () -> URL? = { NotificationServerSettings.serverURL },
        locationProvider: @MainActor @escaping () async throws -> WeatherBriefLocation? = { nil }
    ) {
        self.client = client
        self.cache = cache
        self.cooldown = cooldown
        self.serverURLProvider = serverURLProvider
        self.locationProvider = locationProvider
        self.report = cache.load()
        self.manualRefreshRetryAt = nil
        if report != nil {
            state = .loaded
        }
    }

    func load(minimumInterval: TimeInterval = 0) async {
        guard beginRequest(key: "weather.latest", minimumInterval: minimumInterval) else { return }
        defer { finishRequest(key: "weather.latest") }

        guard let serverURL = serverURLProvider() else {
            cacheNotice = nil
            state = report == nil
                ? .failed(
                    .custom(
                        title: "Brak adresu notifiera",
                        message: "Wpisz Notification server URL w ustawieniach, aby pobrać raport pogodowy.",
                        actionTitle: "Otwórz ustawienia",
                        systemImage: "cloud.sun.fill"
                    )
                )
                : .loaded
            return
        }

        if report == nil {
            state = .loading
        }
        do {
            let location = await resolvedWeatherLocation()
            let loadedReport = try await client.fetchLatestReport(from: serverURL, location: location)
            report = loadedReport
            cache.save(loadedReport)
            cacheNotice = nil
            state = .loaded
        } catch {
            if report != nil {
                cacheNotice = "Pokazuję ostatni zapisany raport. Odświeżenie nie powiodło się."
                state = .loaded
            } else {
                cacheNotice = nil
                state = .failed(.network(error, context: .weather))
            }
        }
    }

    func refreshNow(location: WeatherBriefLocation?) async {
        guard beginRequest(key: "weather.refresh") else { return }
        defer { finishRequest(key: "weather.refresh") }

        guard let serverURL = serverURLProvider() else {
            cacheNotice = nil
            state = report == nil
                ? .failed(
                    .custom(
                        title: "Brak adresu notifiera",
                        message: "Wpisz Notification server URL w ustawieniach, aby odświeżyć aktualną pogodę.",
                        actionTitle: "Otwórz ustawienia",
                        systemImage: "cloud.sun.fill"
                    )
                )
                : .loaded
            return
        }

        if report == nil {
            state = .loading
        }
        do {
            if let location {
                locationNotice = Self.notice(for: location)
            }
            let resolvedLocation: WeatherBriefLocation?
            if let location {
                resolvedLocation = location
            } else {
                resolvedLocation = await resolvedWeatherLocation()
            }
            let loadedReport = try await client.fetchLatestReport(from: serverURL, location: resolvedLocation)
            report = loadedReport
            cache.save(loadedReport)
            manualRefreshRetryAt = nil
            cacheNotice = nil
            state = .loaded
        } catch {
            if report != nil {
                cacheNotice = "Pokazuję ostatni zapisany raport. Odświeżenie aktualnej pogody nie powiodło się."
                state = .loaded
            } else {
                cacheNotice = nil
                state = .failed(.network(error, context: .weather))
            }
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

    private func resolvedWeatherLocation() async -> WeatherBriefLocation? {
        do {
            let location = try await locationProvider()
            locationNotice = location.map(Self.notice(for:))
            return location
        } catch {
            locationNotice = "Używam pogody dla Wrocławia. Lokalizacja jest niedostępna albo odmówiona."
            return nil
        }
    }

    private static func notice(for location: WeatherBriefLocation) -> String {
        if location.city == WeatherBriefLocation.fallback.city {
            return "Prognoza dla: Wrocław."
        }
        return "Prognoza dla: \(location.city)."
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
    enum ClientError: LocalizedError {
        case invalidResponse
        case httpStatus(Int)
        case refreshLocked(Date?)

        var errorDescription: String? {
            switch self {
            case .invalidResponse:
                "Serwer pogody zwrócił nieprawidłową odpowiedź."
            case .httpStatus(let status):
                status == 404
                    ? "Notifier wymaga aktualizacji Dockera. Przebuduj i uruchom ponownie pavbot-notifier."
                    : "Serwer pogody zwrócił HTTP \(status)."
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
        try await send(latestRequest(from: serverURL, location: location))
    }

    func refreshReport(from serverURL: URL, location: WeatherBriefLocation?) async throws -> DailyWeatherReport {
        try await send(refreshRequest(from: serverURL, location: location))
    }

    func latestRequest(from serverURL: URL, location: WeatherBriefLocation?) throws -> URLRequest {
        try request(
            from: serverURL,
            pathComponents: ["v1", "weather", "daily", "latest"],
            method: "GET",
            location: location
        )
    }

    func refreshRequest(from serverURL: URL, location: WeatherBriefLocation?) throws -> URLRequest {
        try request(
            from: serverURL,
            pathComponents: ["v1", "weather", "daily", "refresh"],
            method: "POST",
            location: location
        )
    }

    private func request(
        from serverURL: URL,
        pathComponents: [String],
        method: String,
        location: WeatherBriefLocation?
    ) throws -> URLRequest {
        let endpoint = pathComponents.reduce(serverURL) { partialURL, component in
            partialURL.appendingPathComponent(component)
        }
        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            throw ClientError.invalidResponse
        }
        if let location {
            components.queryItems = [
                URLQueryItem(name: "lat", value: Self.coordinateString(location.latitude)),
                URLQueryItem(name: "lon", value: Self.coordinateString(location.longitude)),
                URLQueryItem(name: "city", value: location.city)
            ]
        }
        guard let url = components.url else {
            throw ClientError.invalidResponse
        }

        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData)
        request.httpMethod = method
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue("no-cache", forHTTPHeaderField: "Pragma")
        request.timeoutInterval = 12
        return request
    }

    private func send(_ request: URLRequest) async throws -> DailyWeatherReport {
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
        return try decoder.decode(DailyWeatherReport.self, from: data)
    }

    private static func coordinateString(_ value: Double) -> String {
        let text = String(format: "%.6f", value)
        return text
            .replacingOccurrences(of: #"0+$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\.$"#, with: "", options: .regularExpression)
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
