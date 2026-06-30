import SwiftUI
import UIKit

struct DiagnosticsView: View {
    @Environment(ManifestStore.self) private var store
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var remoteDeviceToken = ""
    @State private var remoteRegistrationError = ""

    var body: some View {
        GeometryReader { proxy in
            let layout = PavbotAdaptiveLayout.resolve(
                width: proxy.size.width,
                horizontalSizeClass: horizontalSizeClass
            )

            PavbotPremiumScreenScaffold(layout: layout) {
                if let manifest = store.manifest {
                    let diagnostics = ManifestDiagnostics(
                        manifest: manifest,
                        manifestURLString: store.manifestURLString
                    )

                    PavbotCommandHero(
                        eyebrow: "Health Check",
                        title: "Diagnostyka",
                        subtitle: layout.usesDashboardLayout
                            ? "Stan manifestu, automatyzacji i powiadomień jako karty zdrowia połączeń."
                            : "Szybki status danych, problemów i powiadomień bez technicznego podglądu manifestu.",
                        systemImage: "waveform.path.ecg",
                        tint: diagnostics.issues.isEmpty ? .green : .orange,
                        insights: [
                            PavbotInsight(title: "Automatyzacje", value: "\(diagnostics.enabledAutomationCount)", systemImage: "bolt.fill", tint: .yellow),
                            PavbotInsight(title: "Artefakty", value: "\(diagnostics.artifactCount)", systemImage: "tray.full.fill", tint: .blue),
                            PavbotInsight(title: "Tematy", value: "\(diagnostics.topicCount)", systemImage: "folder.fill", tint: .green),
                            PavbotInsight(title: "Problemy", value: "\(diagnostics.issues.count)", systemImage: diagnostics.issues.isEmpty ? "checkmark.seal.fill" : "exclamationmark.triangle.fill", tint: diagnostics.issues.isEmpty ? .green : .orange)
                        ]
                    )

                    DiagnosticsSummarySection(diagnostics: diagnostics)
                    DiagnosticsStatusSection(diagnostics: diagnostics)
                    DiagnosticsIssuesSection(issues: diagnostics.issues)
                    DiagnosticsAutomationSection(statuses: diagnostics.automationStatuses)
                } else {
                    PavbotCommandHero(
                        eyebrow: "Health Check",
                        title: "Diagnostyka",
                        subtitle: "Załaduj manifest Pavbot, aby sprawdzić status automatyzacji Codex.",
                        systemImage: "doc.badge.questionmark",
                        tint: .orange,
                        insights: [
                            PavbotInsight(title: "Manifest", value: "Brak", systemImage: "doc.badge.questionmark", tint: .orange),
                            PavbotInsight(title: "Tryb", value: layout.usesDashboardLayout ? "Wide" : "Phone", systemImage: "rectangle.3.group", tint: .blue)
                        ]
                    )

                    ContentUnavailableView(
                        "Brak manifestu",
                        systemImage: "doc.badge.questionmark",
                        description: Text("Załaduj albo skonfiguruj manifest Pavbot, aby sprawdzić status automatyzacji Codex.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 260)
                }

                DiagnosticsRemoteNotificationSection(
                    deviceToken: remoteDeviceToken,
                    registrationError: remoteRegistrationError
                )
            }
            .environment(\.pavbotAdaptiveLayout, layout)
        }
        .navigationTitle("Diagnostyka")
        .onAppear {
            remoteDeviceToken = RemoteNotificationDiagnostics.deviceToken()
            remoteRegistrationError = RemoteNotificationDiagnostics.registrationError()
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                PavbotRefreshToolbarButton(
                    isRefreshing: store.state == .loading,
                    accessibilityLabel: "Odśwież diagnostykę",
                    accessibilityHint: "Odświeża manifest używany przez diagnostykę."
                ) {
                    Task { await store.reload() }
                }
            }
        }
    }
}

private struct DiagnosticsRemoteNotificationSection: View {
    let deviceToken: String
    let registrationError: String

    var body: some View {
        PavbotReadingCard(
            title: "Powiadomienia live",
            subtitle: "Token jest przechowywany lokalnie i nie trafia do repo.",
            systemImage: "bell.badge.fill",
            tint: .blue
        ) {
            LabeledContent("APNs token", value: RemoteNotificationDiagnostics.deviceTokenPreview(for: deviceToken))
            LabeledContent("Apple Console", value: "Development dla Xcode Debug")

            if !registrationError.isEmpty {
                Label(registrationError, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            Button {
                UIPasteboard.general.string = deviceToken
            } label: {
                Label("Kopiuj token APNs", systemImage: "doc.on.doc")
            }
            .accessibilityLabel("Kopiuj token APNs")
            .accessibilityHint("Kopiuje token urządzenia do Apple Push Notifications Console.")
            .disabled(deviceToken.isEmpty)
        }
    }
}

private struct DiagnosticsSummarySection: View {
    @Environment(\.pavbotAdaptiveLayout) private var layout
    let diagnostics: ManifestDiagnostics

    var body: some View {
        PavbotReadingCard(
            title: "Podsumowanie danych",
            subtitle: "Najważniejsze liczniki manifestu widoczne bez technicznego preview.",
            systemImage: "chart.bar.doc.horizontal.fill",
            tint: .green
        ) {
            LazyVGrid(columns: layout.usesDashboardLayout ? layout.adaptiveColumns(minimum: 180) : [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                MetricTile(title: "Automatyzacje", value: "\(diagnostics.enabledAutomationCount)", systemImage: "bolt.fill", tint: .yellow)
                MetricTile(title: "Artefakty", value: "\(diagnostics.artifactCount)", systemImage: "tray.full.fill", tint: .blue)
                MetricTile(title: "Tematy", value: "\(diagnostics.topicCount)", systemImage: "folder.fill", tint: .green)
                MetricTile(title: "Problemy", value: "\(diagnostics.issues.count)", systemImage: diagnostics.issues.isEmpty ? "checkmark.seal.fill" : "exclamationmark.triangle.fill", tint: diagnostics.issues.isEmpty ? .green : .orange)
            }
        }
    }
}

private struct DiagnosticsStatusSection: View {
    let diagnostics: ManifestDiagnostics

    var body: some View {
        PavbotReadingCard(
            title: "Status danych",
            subtitle: "Czy aplikacja ma aktualne dane i czy publikacje wyglądają zdrowo.",
            systemImage: "checkmark.seal.fill",
            tint: diagnostics.freshness.severity.tint
        ) {
            DiagnosticRow(item: diagnostics.freshness)
        }
    }
}

private struct DiagnosticsIssuesSection: View {
    let issues: [DiagnosticItem]

    var body: some View {
        PavbotReadingCard(
            title: "Problemy",
            subtitle: issues.isEmpty ? "Brak ostrzeżeń diagnostycznych." : "Elementy wymagające sprawdzenia.",
            systemImage: issues.isEmpty ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
            tint: issues.isEmpty ? .green : .orange
        ) {
            if issues.isEmpty {
                Label("Brak ostrzeżeń diagnostycznych", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                ForEach(issues) { issue in
                    DiagnosticRow(item: issue)
                }
            }
        }
    }
}

private struct DiagnosticsAutomationSection: View {
    let statuses: [AutomationDiagnostic]

    var body: some View {
        PavbotReadingCard(
            title: "Aktywne automatyzacje",
            subtitle: "Statusy workflow i ostatni opublikowany artefakt.",
            systemImage: "bolt.circle.fill",
            tint: .yellow
        ) {
            ForEach(statuses) { status in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: status.automation.kind.systemImage)
                            .foregroundStyle(status.automation.kind.tint)
                            .frame(width: 30, height: 30)
                            .background(status.automation.kind.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

                        VStack(alignment: .leading, spacing: 4) {
                            Text(status.automation.name)
                                .font(.headline)
                                .lineLimit(2)
                            Text(status.automation.cadence)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        StatusBadge(text: status.severity.label, systemImage: status.severity.systemImage, tint: status.severity.tint)
                    }

                    if let artifact = status.latestArtifact {
                        HStack(alignment: .top, spacing: 8) {
                            ArtifactIconBadge(kind: artifact.viewerKind)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(artifact.title)
                                    .font(.subheadline.weight(.medium))
                                    .lineLimit(2)
                                Text("\(artifact.type.label) · \(artifact.displayDate)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(artifact.path)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    } else {
                        Label(status.message, systemImage: "tray")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }
}

private struct DiagnosticRow: View {
    let item: DiagnosticItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: item.severity.systemImage)
                .foregroundStyle(item.severity.tint)
                .frame(width: 28, height: 28)
                .background(item.severity.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                Text(item.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

private extension DiagnosticSeverity {
    var label: String {
        switch self {
        case .ok:
            "OK"
        case .warning:
            "Warning"
        case .error:
            "Error"
        }
    }

    var systemImage: String {
        switch self {
        case .ok:
            "checkmark.circle.fill"
        case .warning:
            "exclamationmark.triangle.fill"
        case .error:
            "xmark.octagon.fill"
        }
    }

    var tint: Color {
        switch self {
        case .ok:
            .green
        case .warning:
            .orange
        case .error:
            .red
        }
    }
}
