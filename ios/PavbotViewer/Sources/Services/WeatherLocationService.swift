import CoreLocation
import Foundation

enum WeatherLocationError: Error, Equatable {
    case unavailable
    case denied
}

@MainActor
final class WeatherLocationService: NSObject, CLLocationManagerDelegate {
    private let manager: CLLocationManager
    private let geocoder: CLGeocoder
    private var continuation: CheckedContinuation<WeatherBriefLocation, Error>?
    private var timeoutTask: Task<Void, Never>?

    init(manager: CLLocationManager = CLLocationManager(), geocoder: CLGeocoder = CLGeocoder()) {
        self.manager = manager
        self.geocoder = geocoder
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
    }

    func currentWeatherLocation(mode: WeatherLocationMode = .requestIfNeeded) async throws -> WeatherBriefLocation {
        guard mode != .none else {
            throw WeatherLocationError.unavailable
        }
        guard CLLocationManager.locationServicesEnabled() else {
            throw WeatherLocationError.unavailable
        }

        switch manager.authorizationStatus {
        case .notDetermined:
            guard mode == .requestIfNeeded else {
                throw WeatherLocationError.denied
            }
            return try await waitForWeatherLocation {
                manager.requestWhenInUseAuthorization()
            }
        case .restricted, .denied:
            throw WeatherLocationError.denied
        case .authorizedAlways, .authorizedWhenInUse:
            return try await waitForWeatherLocation {
                manager.requestLocation()
            }
        @unknown default:
            throw WeatherLocationError.unavailable
        }
    }

    private func waitForWeatherLocation(start: () -> Void) async throws -> WeatherBriefLocation {
        try await withCheckedThrowingContinuation { continuation in
            finish(.failure(WeatherLocationError.unavailable))
            self.continuation = continuation
            startTimeout()
            start()
        }
    }

    func weatherLocation(for query: String) async throws -> WeatherBriefLocation {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            throw WeatherLocationError.unavailable
        }
        let placemarks = try await geocodeAddress(trimmedQuery)
        guard let placemark = placemarks.first, let location = placemark.location else {
            throw WeatherLocationError.unavailable
        }

        let city = WeatherLocationDisplayName.name(
            locality: placemark.locality ?? trimmedQuery,
            subAdministrativeArea: placemark.subAdministrativeArea,
            administrativeArea: placemark.administrativeArea,
            country: placemark.country,
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude
        )
        return WeatherBriefLocation(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            city: city
        )
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            switch manager.authorizationStatus {
            case .restricted, .denied:
                finish(.failure(WeatherLocationError.denied))
            case .authorizedAlways, .authorizedWhenInUse:
                manager.requestLocation()
            case .notDetermined:
                break
            @unknown default:
                finish(.failure(WeatherLocationError.unavailable))
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else {
            Task { @MainActor in
                finish(.failure(WeatherLocationError.unavailable))
            }
            return
        }

        Task { @MainActor in
            let city = await displayName(for: location)
            finish(
                .success(
                    WeatherBriefLocation(
                        latitude: location.coordinate.latitude,
                        longitude: location.coordinate.longitude,
                        city: city
                    )
                )
            )
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            finish(.failure(error))
        }
    }

    private func startTimeout() {
        timeoutTask?.cancel()
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            await MainActor.run {
                self?.finish(.failure(WeatherLocationError.unavailable))
            }
        }
    }

    private func finish(_ result: Result<WeatherBriefLocation, Error>) {
        timeoutTask?.cancel()
        timeoutTask = nil
        guard let continuation else { return }
        self.continuation = nil
        switch result {
        case .success(let location):
            continuation.resume(returning: location)
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }

    private func displayName(for location: CLLocation) async -> String {
        do {
            let placemarks = try await reverseGeocode(location)
            if let placemark = placemarks.first {
                return WeatherLocationDisplayName.name(
                    locality: placemark.locality,
                    subAdministrativeArea: placemark.subAdministrativeArea,
                    administrativeArea: placemark.administrativeArea,
                    country: placemark.country,
                    latitude: location.coordinate.latitude,
                    longitude: location.coordinate.longitude
                )
            }
        } catch {
            geocoder.cancelGeocode()
        }

        return WeatherLocationDisplayName.coordinateName(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude
        )
    }

    private func reverseGeocode(_ location: CLLocation) async throws -> [CLPlacemark] {
        try await withCheckedThrowingContinuation { continuation in
            geocoder.reverseGeocodeLocation(location) { placemarks, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: placemarks ?? [])
                }
            }
        }
    }

    private func geocodeAddress(_ query: String) async throws -> [CLPlacemark] {
        try await withCheckedThrowingContinuation { continuation in
            geocoder.geocodeAddressString(query) { placemarks, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: placemarks ?? [])
                }
            }
        }
    }
}

enum WeatherLocationDisplayName {
    static func name(
        locality: String?,
        subAdministrativeArea: String?,
        administrativeArea: String?,
        country: String?,
        latitude: Double,
        longitude: Double
    ) -> String {
        let primary = firstNonBlank(locality, subAdministrativeArea, administrativeArea)
        let secondary = firstNonBlank(
            administrativeArea == primary ? nil : administrativeArea,
            country == primary ? nil : country
        )
        let parts = [primary, secondary]
            .compactMap { trimmed($0) }
            .removingDuplicates()

        return parts.isEmpty
            ? coordinateName(latitude: latitude, longitude: longitude)
            : parts.joined(separator: ", ")
    }

    static func coordinateName(latitude: Double, longitude: Double) -> String {
        String(format: "%.2f, %.2f", latitude, longitude)
    }

    private static func firstNonBlank(_ values: String?...) -> String? {
        values.compactMap { trimmed($0) }.first
    }

    private static func trimmed(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

private extension Array where Element == String {
    func removingDuplicates() -> [String] {
        var seen: Set<String> = []
        return filter { seen.insert($0).inserted }
    }
}
