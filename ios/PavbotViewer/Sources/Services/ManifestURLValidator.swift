import Foundation

enum ManifestURLValidationResult: Equatable {
    case valid
    case invalid(String)

    var message: String? {
        if case .invalid(let message) = self {
            return message
        }
        return nil
    }
}

enum ManifestURLValidator {
    static func validate(_ value: String) -> ManifestURLValidationResult {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .invalid("Wpisz adres URL manifestu.")
        }
        guard let url = URL(string: trimmed), let scheme = url.scheme else {
            return .invalid("Wpisz poprawny adres URL manifestu.")
        }
        guard scheme == "https" else {
            return .invalid("Użyj adresu URL manifestu z HTTPS.")
        }
        guard url.pathExtension.lowercased() == "json" else {
            return .invalid("Adres URL manifestu musi wskazywać plik JSON.")
        }
        return .valid
    }
}
