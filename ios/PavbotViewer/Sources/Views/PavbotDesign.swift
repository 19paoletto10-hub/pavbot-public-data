import SwiftUI

struct PavbotUserFacingError: Equatable {
    enum Context: Equatable {
        case manifest
        case jobs
        case weather
        case notifier
        case audio
        case preview
    }

    let title: String
    let message: String
    let actionTitle: String
    let systemImage: String
    let tint: Color

    static func == (lhs: PavbotUserFacingError, rhs: PavbotUserFacingError) -> Bool {
        lhs.title == rhs.title
            && lhs.message == rhs.message
            && lhs.actionTitle == rhs.actionTitle
            && lhs.systemImage == rhs.systemImage
    }

    static func manifest(_ message: String) -> PavbotUserFacingError {
        PavbotUserFacingError(
            title: "Manifest wymaga konfiguracji",
            message: "Wklej publiczny GitHub raw manifest URL w ustawieniach. \(polishMessage(from: message))",
            actionTitle: "Otwórz ustawienia",
            systemImage: "doc.badge.gearshape",
            tint: .orange
        )
    }

    static func custom(
        title: String,
        message: String,
        actionTitle: String = "Spróbuj ponownie",
        systemImage: String = "exclamationmark.triangle",
        tint: Color = .orange
    ) -> PavbotUserFacingError {
        PavbotUserFacingError(
            title: title,
            message: polishMessage(from: message),
            actionTitle: actionTitle,
            systemImage: systemImage,
            tint: tint
        )
    }

    static func network(_ error: Error, context: Context) -> PavbotUserFacingError {
        let rawMessage = polishMessage(from: error.localizedDescription)
        switch context {
        case .weather:
            return PavbotUserFacingError(
                title: "Nie udało się pobrać pogody",
                message: "Sprawdź połączenie z notifierem i spróbuj ponownie. Szczegóły: \(rawMessage)",
                actionTitle: "Spróbuj ponownie",
                systemImage: "cloud.sun.fill",
                tint: .blue
            )
        case .jobs:
            return PavbotUserFacingError(
                title: "Nie udało się pobrać danych Jobs",
                message: "Aplikacja pokaże ostatnie zapisane dane, jeśli są dostępne. Szczegóły: \(rawMessage)",
                actionTitle: "Odśwież dane",
                systemImage: "briefcase.fill",
                tint: .indigo
            )
        case .notifier:
            return PavbotUserFacingError(
                title: "Notifier jest niedostępny",
                message: "Sprawdź Docker, Cloudflare Tunnel i adres serwera powiadomień. Szczegóły: \(rawMessage)",
                actionTitle: "Sprawdź status",
                systemImage: "antenna.radiowaves.left.and.right",
                tint: .orange
            )
        case .preview:
            return PavbotUserFacingError(
                title: "Nie udało się otworzyć podglądu",
                message: "Plik może być chwilowo niedostępny albo manifest wskazuje nieaktualny URL. Szczegóły: \(rawMessage)",
                actionTitle: "Spróbuj ponownie",
                systemImage: "doc.text.magnifyingglass",
                tint: .red
            )
        case .audio:
            return audio(rawMessage)
        case .manifest:
            return manifest(rawMessage)
        }
    }

    static func audio(_ message: String) -> PavbotUserFacingError {
        PavbotUserFacingError(
            title: "Nie udało się odtworzyć audio",
            message: polishMessage(from: message),
            actionTitle: "Otwórz plik źródłowy",
            systemImage: "waveform.badge.exclamationmark",
            tint: .purple
        )
    }

    static func preview(_ message: String) -> PavbotUserFacingError {
        PavbotUserFacingError(
            title: "Podgląd jest niedostępny",
            message: polishMessage(from: message),
            actionTitle: "Otwórz plik źródłowy",
            systemImage: "doc.text.magnifyingglass",
            tint: .red
        )
    }

    static func polishMessage(from message: String) -> String {
        switch message {
        case let value where value.contains("Set your public GitHub raw manifest URL"):
            "Wklej adres GitHub raw manifest URL, którego używa repozytorium automatyzacji."
        case let value where value.contains("Enter a valid manifest URL"):
            "Wpisz poprawny adres manifestu."
        case let value where value.contains("Showing cached data"):
            "Pokazuję dane z pamięci, bo odświeżenie nie powiodło się."
        case let value where value.contains("Reddit OAuth credentials"):
            "Radar memów wymaga konfiguracji Reddit OAuth w notifierze."
        case let value where value.contains("cancelled") || value.contains("The request timed out"):
            "Połączenie trwało zbyt długo. Sprawdź internet, Docker i Cloudflare Tunnel."
        case let value where value.contains("offline") || value.contains("not connected"):
            "Brak połączenia z siecią albo serwer notifiera jest niedostępny."
        case let value where value.isEmpty:
            "Spróbuj ponownie za chwilę."
        default:
            message
        }
    }
}

enum PavbotLoadState: Equatable {
    case idle
    case loading
    case loaded
    case failed(PavbotUserFacingError)

    var isLoading: Bool {
        self == .loading
    }

    var error: PavbotUserFacingError? {
        if case .failed(let error) = self {
            return error
        }
        return nil
    }
}

struct PavbotScreenHeader: View {
    let title: String
    let subtitle: String
    let systemImage: String
    var tint: Color = .accentColor

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: systemImage)
                .font(.title2.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 50, height: 50)
                .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.title2.weight(.bold))
                    .fixedSize(horizontal: false, vertical: true)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct PavbotStateView: View {
    let error: PavbotUserFacingError
    var action: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: error.systemImage)
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(error.tint)
                .frame(width: 52, height: 52)
                .background(error.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            VStack(alignment: .leading, spacing: 7) {
                Text(error.title)
                    .font(.headline.weight(.semibold))
                Text(error.message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let action {
                Button(action: action) {
                    Label(error.actionTitle, systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct PavbotActionRow: View {
    let title: String
    let subtitle: String
    let systemImage: String
    var tint: Color = .accentColor

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: systemImage)
                .font(.headline.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 38, height: 38)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

struct PavbotConnectionCard<Content: View>: View {
    let title: String
    let subtitle: String
    let systemImage: String
    var tint: Color = .accentColor
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            PavbotScreenHeader(title: title, subtitle: subtitle, systemImage: systemImage, tint: tint)
            content()
        }
        .padding(18)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(tint.opacity(0.10), lineWidth: 1)
        }
    }
}

struct PavbotCacheNoticeBanner: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "externaldrive.fill.badge.checkmark")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.orange)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.11), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct MetricTile: View {
    let title: String
    let value: String
    var subtitle: String?
    let systemImage: String
    var tint: Color = .accentColor

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: systemImage)
                .font(.headline)
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

            Text(value)
                .font(.title2.weight(.semibold))
                .monospacedDigit()

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}

struct StatusBadge: View {
    let text: String
    let systemImage: String
    var tint: Color = .accentColor

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .foregroundStyle(tint)
            .background(tint.opacity(0.12), in: Capsule())
    }
}

struct ArtifactIconBadge: View {
    let kind: ArtifactViewerKind

    var body: some View {
        Image(systemName: kind.systemImage)
            .font(.headline)
            .foregroundStyle(kind.tint)
            .frame(width: 38, height: 38)
            .background(kind.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }
}

extension ArtifactViewerKind {
    var systemImage: String {
        switch self {
        case .markdown:
            "doc.text"
        case .pdf:
            "doc.richtext"
        case .audio:
            "waveform"
        case .json:
            "curlybraces"
        case .file:
            "doc"
        }
    }

    var tint: Color {
        switch self {
        case .markdown:
            .blue
        case .pdf:
            .red
        case .audio:
            .purple
        case .json:
            .orange
        case .file:
            .secondary
        }
    }
}

extension Int {
    var fileSizeLabel: String {
        ByteCountFormatter.string(fromByteCount: Int64(self), countStyle: .file)
    }
}
