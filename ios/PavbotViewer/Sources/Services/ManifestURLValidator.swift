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
            return .invalid("Enter a manifest URL.")
        }
        guard let url = URL(string: trimmed), let scheme = url.scheme else {
            return .invalid("Enter a valid manifest URL.")
        }
        guard scheme == "https" else {
            return .invalid("Use an HTTPS manifest URL.")
        }
        guard url.pathExtension.lowercased() == "json" else {
            return .invalid("Manifest URL must point to a JSON file.")
        }
        return .valid
    }
}
