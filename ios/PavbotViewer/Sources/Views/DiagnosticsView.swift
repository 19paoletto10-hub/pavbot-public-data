import SwiftUI
import UIKit

struct DiagnosticsView: View {
    @Environment(ManifestStore.self) private var store
    @State private var remoteDeviceToken = ""
    @State private var remoteRegistrationError = ""

    var body: some View {
        List {
            if let manifest = store.manifest {
                let diagnostics = ManifestDiagnostics(
                    manifest: manifest,
                    manifestURLString: store.manifestURLString
                )

                DiagnosticsSummarySection(diagnostics: diagnostics)
                DiagnosticsStatusSection(diagnostics: diagnostics)
                DiagnosticsIssuesSection(issues: diagnostics.issues)
                DiagnosticsAutomationSection(statuses: diagnostics.automationStatuses)
            } else {
                ContentUnavailableView(
                    "Brak manifestu",
                    systemImage: "doc.badge.questionmark",
                    description: Text("Załaduj albo skonfiguruj manifest Pavbot, aby sprawdzić status automatyzacji Codex.")
                )
            }

            DiagnosticsRemoteNotificationSection(
                deviceToken: remoteDeviceToken,
                registrationError: remoteRegistrationError
            )
        }
        .navigationTitle("Diagnostyka")
        .listStyle(.insetGrouped)
        .onAppear {
            remoteDeviceToken = RemoteNotificationDiagnostics.deviceToken()
            remoteRegistrationError = RemoteNotificationDiagnostics.registrationError()
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await store.reload() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel("Odśwież diagnostykę")
            }
        }
    }
}

private struct DiagnosticsRemoteNotificationSection: View {
    let deviceToken: String
    let registrationError: String

    var body: some View {
        Section {
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
        } header: {
            Text("Powiadomienia live")
        } footer: {
            Text("Użyj tego tokena w Apple Push Notifications Console dla com.paweltanski.pavbotviewer. Token jest przechowywany lokalnie i nie trafia do repo.")
        }
    }
}

private struct DiagnosticsSummarySection: View {
    let diagnostics: ManifestDiagnostics

    var body: some View {
        Section {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                MetricTile(title: "Automatyzacje", value: "\(diagnostics.enabledAutomationCount)", systemImage: "bolt.fill", tint: .yellow)
                MetricTile(title: "Artefakty", value: "\(diagnostics.artifactCount)", systemImage: "tray.full.fill", tint: .blue)
                MetricTile(title: "Tematy", value: "\(diagnostics.topicCount)", systemImage: "folder.fill", tint: .green)
                MetricTile(title: "Problemy", value: "\(diagnostics.issues.count)", systemImage: diagnostics.issues.isEmpty ? "checkmark.seal.fill" : "exclamationmark.triangle.fill", tint: diagnostics.issues.isEmpty ? .green : .orange)
            }
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
    }
}

private struct DiagnosticsStatusSection: View {
    let diagnostics: ManifestDiagnostics

    var body: some View {
        Section {
            DiagnosticRow(item: diagnostics.freshness)
            DiagnosticRow(item: diagnostics.urlStatus)
            DiagnosticRow(item: diagnostics.rawBaseURLStatus)
        } header: {
            Text("Manifest Codex")
        } footer: {
            Text("Status jest wyliczany z manifestu Pavbot i wygenerowanych artefaktów.")
        }
    }
}

private struct DiagnosticsIssuesSection: View {
    let issues: [DiagnosticItem]

    var body: some View {
        Section("Problemy") {
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
        Section("Aktywne automatyzacje") {
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
