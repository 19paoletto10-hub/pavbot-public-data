import Foundation

enum DiagnosticSeverity: Equatable {
    case ok
    case warning
    case error
}

struct DiagnosticItem: Identifiable, Equatable {
    let id: String
    let severity: DiagnosticSeverity
    let title: String
    let message: String
}

struct AutomationDiagnostic: Identifiable, Equatable {
    var id: String { automation.id }

    let automation: PavbotAutomation
    let latestArtifact: PavbotArtifact?
    let severity: DiagnosticSeverity
    let message: String
}

struct ManifestDiagnostics: Equatable {
    static let defaultPlaceholderManifestURL = "https://raw.githubusercontent.com/OWNER/REPO/main/public/pavbot-manifest.json"

    let enabledAutomationCount: Int
    let topicCount: Int
    let artifactCount: Int
    let generatedAtDate: Date?
    let freshness: DiagnosticItem
    let urlStatus: DiagnosticItem
    let rawBaseURLStatus: DiagnosticItem
    let automationStatuses: [AutomationDiagnostic]
    let issues: [DiagnosticItem]

    init(
        manifest: PavbotManifest,
        manifestURLString: String,
        now: Date = Date(),
        staleAfter: TimeInterval = 24 * 60 * 60
    ) {
        enabledAutomationCount = manifest.enabledAutomations.count
        topicCount = manifest.topics.count
        artifactCount = manifest.artifacts.count
        generatedAtDate = Self.parseGeneratedAt(manifest.generatedAt)
        freshness = Self.freshnessItem(generatedAtDate: generatedAtDate, now: now, staleAfter: staleAfter)
        urlStatus = Self.urlStatusItem(manifestURLString: manifestURLString)
        rawBaseURLStatus = Self.rawBaseURLStatusItem(rawBaseURL: manifest.rawBaseUrl)
        automationStatuses = manifest.enabledAutomations.map { automation in
            let latestArtifact = manifest.latestArtifact(for: automation)
            return AutomationDiagnostic(
                automation: automation,
                latestArtifact: latestArtifact,
                severity: latestArtifact == nil ? .warning : .ok,
                message: latestArtifact.map { "Ostatni wynik: \($0.displayDate)" } ?? "Nie znaleziono wygenerowanych plików dla tematu tej automatyzacji."
            )
        }

        var collectedIssues = [freshness, urlStatus, rawBaseURLStatus].filter { $0.severity != .ok }
        collectedIssues.append(contentsOf: automationStatuses.compactMap { status in
            guard status.severity != .ok else { return nil }
            return DiagnosticItem(
                id: "automation-\(status.automation.id)",
                severity: status.severity,
                title: "Automatyzacja nie ma artefaktów",
                message: "\(status.automation.name) nie ma wygenerowanych plików w \(status.automation.topicPath)."
            )
        })
        issues = collectedIssues
    }

    private static func freshnessItem(generatedAtDate: Date?, now: Date, staleAfter: TimeInterval) -> DiagnosticItem {
        guard let generatedAtDate else {
            return DiagnosticItem(
                id: "freshness-invalid",
                severity: .error,
                title: "Niepoprawny czas manifestu",
                message: "Nie udało się odczytać wartości generatedAt w manifeście."
            )
        }

        let age = now.timeIntervalSince(generatedAtDate)
        if age > staleAfter {
            return DiagnosticItem(
                id: "freshness-stale",
                severity: .warning,
                title: "Manifest jest nieaktualny",
                message: "Manifest ma więcej niż 24 godziny."
            )
        }

        return DiagnosticItem(
            id: "freshness-ok",
            severity: .ok,
            title: "Manifest jest aktualny",
            message: "Manifest został wygenerowany w ostatnich 24 godzinach."
        )
    }

    private static func urlStatusItem(manifestURLString: String) -> DiagnosticItem {
        let trimmed = manifestURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == defaultPlaceholderManifestURL {
            return DiagnosticItem(
                id: "manifest-url-placeholder",
                severity: .warning,
                title: "Manifest URL jest placeholderem",
                message: "Ustaw publiczny GitHub raw Manifest URL w ustawieniach."
            )
        }

        switch ManifestURLValidator.validate(trimmed) {
        case .valid:
            return DiagnosticItem(
                id: "manifest-url-ok",
                severity: .ok,
                title: "Manifest URL skonfigurowany",
                message: "Manifest URL wskazuje plik JSON po HTTPS."
            )
        case .invalid(let message):
            return DiagnosticItem(
                id: "manifest-url-invalid",
                severity: .error,
                title: "Manifest URL jest niepoprawny",
                message: message
            )
        }
    }

    private static func rawBaseURLStatusItem(rawBaseURL: String) -> DiagnosticItem {
        let trimmed = rawBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return DiagnosticItem(
                id: "raw-base-missing",
                severity: .warning,
                title: "Brakuje publicznego raw base URL",
                message: "Podglądy użyją ścieżek względnych, dopóki manifest nie zostanie wygenerowany z publicznym raw base URL."
            )
        }

        guard let url = URL(string: trimmed), url.scheme == "https" else {
            return DiagnosticItem(
                id: "raw-base-invalid",
                severity: .warning,
                title: "Public raw base URL nie używa HTTPS",
                message: "Użyj GitHub raw base URL po HTTPS, aby podglądy działały stabilnie."
            )
        }

        return DiagnosticItem(
            id: "raw-base-ok",
            severity: .ok,
            title: "Public raw base URL skonfigurowany",
            message: "Podglądy artefaktów mogą rozwiązywać publiczne linki raw."
        )
    }

    private static func parseGeneratedAt(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) {
            return date
        }

        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]
        return standard.date(from: value)
    }
}
