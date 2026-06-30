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

private enum WeatherBriefStoreError: LocalizedError, Equatable {
    case mismatchedLocation(expected: String, actual: String)

    var errorDescription: String? {
        switch self {
        case .mismatchedLocation(let expected, let actual):
            "Serwer zwrócił raport dla lokalizacji \(actual), a wybrana lokalizacja to \(expected). Odśwież notifier i spróbuj ponownie."
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
    private let manualLocationProvider: () -> WeatherBriefLocation?
    @ObservationIgnored private let reloadGate = ReloadGate()

    init(
        client: any WeatherBriefFetching = WeatherBriefClient(),
        cache: WeatherBriefCache = WeatherBriefCache(),
        cooldown: WeatherRefreshCooldown = WeatherRefreshCooldown(),
        serverURLProvider: @escaping () -> URL? = { NotificationServerSettings.serverURL },
        locationProvider: @MainActor @escaping (WeatherLocationMode) async throws -> WeatherBriefLocation? = { _ in nil },
        manualLocationProvider: @escaping () -> WeatherBriefLocation? = { ManualWeatherLocationSettings.location() }
    ) {
        self.client = client
        self.cache = cache
        self.cooldown = cooldown
        self.serverURLProvider = serverURLProvider
        self.locationProvider = locationProvider
        self.manualLocationProvider = manualLocationProvider
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
        await loadLatest(minimumInterval: minimumInterval, locationMode: .useIfAuthorized)
    }

    private func loadLatest(minimumInterval: TimeInterval = 0, locationMode: WeatherLocationMode) async {
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
        let previousNotice = locationNotice
        var requestedLocation: WeatherBriefLocation?
        do {
            let resolvedLocation: WeatherBriefLocation?
            if let location {
                resolvedLocation = location
            } else {
                resolvedLocation = await resolvedWeatherLocation(mode: .useIfAuthorized)
            }
            requestedLocation = resolvedLocation
            if let resolvedLocation {
                locationNotice = Self.loadingNotice(for: resolvedLocation)
            }
            let loadedReport = try await client.fetchLatestReport(from: serverURL, location: resolvedLocation)
            try Self.validate(loadedReport, matches: resolvedLocation)
            report = loadedReport
            cache.save(loadedReport)
            locationNotice = Self.successNotice(for: resolvedLocation, report: loadedReport, currentNotice: locationNotice)
            manualRefreshRetryAt = nil
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
        if let manualLocation = manualLocationProvider() {
            locationNotice = Self.notice(for: manualLocation)
            return manualLocation
        }

        guard mode != .none else {
            locationNotice = Self.notice(for: .fallback)
            return nil
        }
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
                message: "Sprawdź połączenie z notifierem i spróbuj ponownie. Szczegóły: \(error.localizedDescription)",
                actionTitle: "Spróbuj ponownie",
                systemImage: "cloud.sun.fill",
                tint: .blue
            )
        }

        return .network(error, context: .weather)
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
