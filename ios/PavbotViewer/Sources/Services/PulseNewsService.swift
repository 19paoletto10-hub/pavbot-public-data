import Foundation

struct PulseNewsClient {
    var fetchData: @Sendable (URL) async throws -> Data

    init(fetchData: (@Sendable (URL) async throws -> Data)? = nil) {
        self.fetchData = fetchData ?? { url in
            try await PulseNewsClient.defaultFetchData(url: url)
        }
    }

    func fetchData(_ url: URL) async throws -> Data {
        try await fetchData(url)
    }

    private static func defaultFetchData(url: URL) async throws -> Data {
        do {
            return try await PavbotHTTPClient().data(for: url)
        } catch PavbotHTTPClientError.invalidResponse {
            throw PulseNewsClientError.invalidResponse
        } catch PavbotHTTPClientError.httpStatus(let status) {
            throw PulseNewsClientError.httpStatus(status)
        }
    }
}

enum PulseNewsClientError: LocalizedError, Equatable {
    case invalidResponse
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "Serwer danych Pulsu dnia zwrócił nieprawidłową odpowiedź."
        case .httpStatus(let statusCode):
            "Serwer danych Pulsu dnia zwrócił HTTP \(statusCode)."
        }
    }
}
