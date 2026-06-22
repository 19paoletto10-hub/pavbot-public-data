import SwiftUI
import UserNotifications

struct SettingsView: View {
    @Environment(ManifestStore.self) private var store
    @Environment(AppRouter.self) private var router
    @State private var draftURL = ""
    @State private var notificationStatus = "Not checked"
    @State private var manifestURLValidationMessage: String?

    var body: some View {
        Form {
            Section("Manifest") {
                TextField("Manifest URL", text: $draftURL, axis: .vertical)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(.body, design: .monospaced))

                Text("Use a public GitHub raw manifest URL, for example https://raw.githubusercontent.com/<owner>/<repo>/<branch>/public/pavbot-manifest.json. Private repositories require a later OAuth or backend proxy integration.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let manifestURLValidationMessage {
                    Label(manifestURLValidationMessage, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                Button {
                    saveManifestURL()
                } label: {
                    Label("Save and reload", systemImage: "arrow.clockwise")
                }
            }

            if let manifest = store.manifest {
                Section("Loaded") {
                    LabeledContent("Automations", value: "\(manifest.automations.count)")
                    LabeledContent("Topics", value: "\(manifest.topics.count)")
                    LabeledContent("Artifacts", value: "\(manifest.artifacts.count)")
                    LabeledContent("Generated", value: manifest.generatedAt)
                }
            }

            Section("Notifications") {
                LabeledContent("Status", value: notificationStatus)
                Button {
                    Task { await requestNotifications() }
                } label: {
                    Label("Enable file alerts", systemImage: "bell.badge")
                }
            }

            Section("Diagnostics") {
                Button {
                    router.selectedTab = .diagnostics
                } label: {
                    Label("Open Codex diagnostics", systemImage: "waveform.path.ecg")
                }
            }
        }
        .navigationTitle("Settings")
        .onAppear {
            draftURL = store.manifestURLString
            manifestURLValidationMessage = ManifestURLValidator.validate(draftURL).message
            Task { await refreshNotificationStatus() }
        }
        .onChange(of: draftURL) { _, newValue in
            manifestURLValidationMessage = ManifestURLValidator.validate(newValue).message
        }
    }

    private func saveManifestURL() {
        let trimmed = draftURL.trimmingCharacters(in: .whitespacesAndNewlines)
        switch ManifestURLValidator.validate(trimmed) {
        case .valid:
            manifestURLValidationMessage = nil
            store.manifestURLString = trimmed
            Task { await store.reload() }
        case .invalid(let message):
            manifestURLValidationMessage = message
        }
    }

    private func refreshNotificationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationStatus = settings.authorizationStatus.label
    }

    private func requestNotifications() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        await refreshNotificationStatus()
    }
}

private extension UNAuthorizationStatus {
    var label: String {
        switch self {
        case .notDetermined:
            "Not requested"
        case .denied:
            "Denied"
        case .authorized:
            "Enabled"
        case .provisional:
            "Provisional"
        case .ephemeral:
            "Ephemeral"
        @unknown default:
            "Unknown"
        }
    }
}
