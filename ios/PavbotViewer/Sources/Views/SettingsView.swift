import SwiftUI
import UIKit
import UserNotifications

struct SettingsView: View {
    @Environment(ManifestStore.self) private var store
    @Environment(AppRouter.self) private var router
    @State private var draftURL = ""
    @State private var draftNotificationServerURL = ""
    @State private var notificationStatus = "Not checked"
    @State private var remoteDeviceToken = ""
    @State private var remoteRegistrationError = ""
    @State private var manifestURLValidationMessage: String?
    @State private var notificationServerValidationMessage: String?

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
                TextField("Notification server URL", text: $draftNotificationServerURL, axis: .vertical)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(.body, design: .monospaced))

                Text("Use your MacBook or server notifier URL, for example https://notify.example.com. Check https://notify.example.com/status before enabling alerts. Live notifications stay off until this URL is saved and permission is granted.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let notificationServerValidationMessage {
                    Label(notificationServerValidationMessage, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                Button {
                    Task { await requestNotifications() }
                } label: {
                    Label("Enable file alerts", systemImage: "bell.badge")
                }

                LabeledContent("APNs device token", value: RemoteNotificationDiagnostics.deviceTokenPreview(for: remoteDeviceToken))

                if !remoteRegistrationError.isEmpty {
                    Label(remoteRegistrationError, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                Button {
                    UIPasteboard.general.string = remoteDeviceToken
                } label: {
                    Label("Copy APNs device token", systemImage: "doc.on.doc")
                }
                .disabled(remoteDeviceToken.isEmpty)

                Text("Use this token in Apple Push Notifications Console. Select Development for Xcode-installed PavbotViewerPush builds and Production for TestFlight.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
            draftNotificationServerURL = NotificationServerSettings.serverURLString
            manifestURLValidationMessage = ManifestURLValidator.validate(draftURL).message
            notificationServerValidationMessage = NotificationServerSettings.validationMessage(for: draftNotificationServerURL, required: false)
            refreshRemoteNotificationDiagnostics()
            Task { await refreshNotificationStatus() }
        }
        .onChange(of: draftURL) { _, newValue in
            manifestURLValidationMessage = ManifestURLValidator.validate(newValue).message
        }
        .onChange(of: draftNotificationServerURL) { _, newValue in
            notificationServerValidationMessage = NotificationServerSettings.validationMessage(for: newValue, required: false)
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
        let trimmedServerURL = draftNotificationServerURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if let message = NotificationServerSettings.validationMessage(for: trimmedServerURL, required: true) {
            notificationServerValidationMessage = message
            return
        }

        NotificationServerSettings.serverURLString = trimmedServerURL
        LiveNotificationOnboarding.markPromptSeen()
        _ = await RemoteNotificationPermission.requestAndRegister()
        await refreshNotificationStatus()
        refreshRemoteNotificationDiagnostics()
    }

    private func refreshRemoteNotificationDiagnostics() {
        remoteDeviceToken = RemoteNotificationDiagnostics.deviceToken()
        remoteRegistrationError = RemoteNotificationDiagnostics.registrationError()
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
