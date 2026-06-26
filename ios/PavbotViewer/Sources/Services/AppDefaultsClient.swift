import Foundation

struct AppConnectionDefaults: Decodable, Equatable {
    let schemaVersion: Int
    let manifestURL: String
    let notificationServerURL: String
    let statusURL: String

    var validationError: String? {
        if let message = ManifestURLValidator.validate(manifestURL).message {
            return "Manifest URL: \(message)"
        }
        if let message = NotificationServerSettings.validationMessage(for: notificationServerURL, required: true) {
            return "Notification server URL: \(message)"
        }
        return nil
    }
}

enum AppDefaultsClientError: LocalizedError, Equatable {
    case missingBootstrapURL
    case invalidResponse
    case httpStatus(Int)
    case invalidDefaults(String)

    var errorDescription: String? {
        switch self {
        case .missingBootstrapURL:
            "Brakuje wbudowanego adresu Pavbot Notifier."
        case .invalidResponse:
            "Serwer domyślnych ustawień zwrócił nieprawidłową odpowiedź."
        case .httpStatus(let status):
            "Serwer domyślnych ustawień zwrócił HTTP \(status)."
        case .invalidDefaults(let message):
            "Domyślne ustawienia są niepoprawne. \(message)"
        }
    }
}

struct AppDefaultsClient {
    static let bootstrapNotifierURLString = "https://married-smart-employer-sends.trycloudflare.com"

    var fetchData: @Sendable (URL) async throws -> Data

    init(fetchData: (@Sendable (URL) async throws -> Data)? = nil) {
        self.fetchData = fetchData ?? { url in
            var request = URLRequest(url: url)
            request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            request.timeoutInterval = 8
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw AppDefaultsClientError.invalidResponse
            }
            guard (200..<300).contains(httpResponse.statusCode) else {
                throw AppDefaultsClientError.httpStatus(httpResponse.statusCode)
            }
            return data
        }
    }

    func fetchDefaults(preferredServerURLString: String) async throws -> AppConnectionDefaults {
        guard let endpoint = Self.defaultsEndpointURL(preferredServerURLString: preferredServerURLString) else {
            throw AppDefaultsClientError.missingBootstrapURL
        }
        let data = try await fetchData(endpoint)
        let defaults = try JSONDecoder.pavbot.decode(AppConnectionDefaults.self, from: data)
        if let validationError = defaults.validationError {
            throw AppDefaultsClientError.invalidDefaults(validationError)
        }
        return defaults
    }

    static func defaultsEndpointURL(preferredServerURLString: String) -> URL? {
        let preferred = preferredServerURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseURLString: String
        if NotificationServerSettings.validationMessage(for: preferred, required: true) == nil {
            baseURLString = preferred
        } else {
            baseURLString = bootstrapNotifierURLString
        }
        guard let baseURL = URL(string: baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return nil
        }
        return baseURL.appendingPathComponent("v1/app/defaults")
    }
}
