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
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw PulseNewsClientError.httpStatus(http.statusCode)
        }
        return data
    }
}

enum PulseNewsClientError: LocalizedError, Equatable {
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .httpStatus(let statusCode):
            "Serwer danych Pulsu dnia zwrócił HTTP \(statusCode)."
        }
    }
}
