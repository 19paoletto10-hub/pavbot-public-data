import SwiftUI
import UIKit
import UserNotifications

struct SettingsView: View {
    @Environment(ManifestStore.self) private var store
    @Environment(AppAppearanceStore.self) private var appearanceStore
    @Environment(PavbotHaptics.self) private var haptics
    @State private var draftURL = ""
    @State private var draftNotificationServerURL = ""
    @State private var notificationStatus = "Nie sprawdzono"
    @State private var liveAlertsStatus = "Wyłączone"
    @State private var notificationServerReachability = "Nie sprawdzono"
    @State private var deviceTokenRegistrationStatus = "Nie zarejestrowano"
    @State private var deviceTokenRegisteredAt = ""
    @State private var remoteDeviceToken = ""
    @State private var remoteRegistrationError = ""
    @State private var dailyWeatherAlertsEnabled = true
    @State private var manifestURLValidationMessage: String?
    @State private var notificationServerValidationMessage: String?
    @State private var defaultConnectionSettingsStatus: String?
    @State private var isRestoringDefaultConnectionSettings = false

    var body: some View {
        @Bindable var appearanceStore = appearanceStore

        Form {
            Section("Wygląd") {
                Picker("Motyw aplikacji", selection: $appearanceStore.preference) {
                    ForEach(AppAppearancePreference.allCases) { preference in
                        Text(preference.title).tag(preference)
                    }
                }
                .pickerStyle(.segmented)

                Text("Auto używa ustawień systemu iOS. Jasny oraz Ciemny wymuszają wygląd tylko w Pavbot.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Dostępność i komfort") {
                Toggle(isOn: hapticToggleBinding) {
                    Label("Dotyk interakcji", systemImage: "hand.tap.fill")
                }

                Text("Subtelna haptyka działa przy zmianie zakładek, zapisie artykułów, swipe w Pulsie Dnia i akcjach audio. Na urządzeniach bez Taptic Engine pozostaje bezpiecznie wyciszona.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Pavbot korzysta z natywnych ustawień iOS. Te funkcje możesz pokazać w App Store Connect jako realnie wspierane po testach na urządzeniu.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 12)], spacing: 12) {
                    ForEach(AccessibilityShowcaseFeature.allCases) { feature in
                        AccessibilityShowcaseCard(feature: feature)
                    }
                }
                .padding(.vertical, 4)

                Label("Nie deklaruj Audio Descriptions w v1, bo aplikacja nie ma osobnych opisów audio dla treści wizualnych.", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("Domyślne połączenia") {
                Button {
                    Task { await restoreDefaultConnectionSettings() }
                } label: {
                    Label(
                        isRestoringDefaultConnectionSettings ? "Pobieram ustawienia..." : "Przywróć ustawienia domyślne",
                        systemImage: "arrow.counterclockwise.circle"
                    )
                }
                .disabled(isRestoringDefaultConnectionSettings)

                Text("Aplikacja pobierze aktualny Manifest URL i Notification server URL z Pavbot Notifier. Ręczna edycja pól nadal działa.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let defaultConnectionSettingsStatus {
                    Label(defaultConnectionSettingsStatus, systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(defaultConnectionSettingsStatus.hasPrefix("Przywrócono") ? .green : .orange)
                }
            }

            Section("Manifest") {
                TextField("Manifest URL", text: $draftURL, axis: .vertical)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(.body, design: .monospaced))

                Text("Użyj adresu typu public GitHub raw manifest URL, np. https://raw.githubusercontent.com/<owner>/<repo>/<branch>/public/pavbot-manifest.json. Prywatne repozytoria wymagają osobnego OAuth albo backend proxy.")
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
                    Label("Zapisz i odśwież", systemImage: "arrow.clockwise")
                }
            }

            if let manifest = store.manifest {
                Section("Załadowane dane") {
                    LabeledContent("Automatyzacje", value: "\(manifest.automations.count)")
                    LabeledContent("Tematy", value: "\(manifest.topics.count)")
                    LabeledContent("Artefakty", value: "\(manifest.artifacts.count)")
                    LabeledContent("Wygenerowano", value: manifest.generatedAt)
                }
            }

            Section("Powiadomienia") {
                LabeledContent("Status", value: notificationStatus)
                LabeledContent("Alerty live", value: liveAlertsStatus)
                LabeledContent("Serwer dostępny", value: notificationServerReachability)
                LabeledContent("Token urządzenia", value: deviceTokenRegistrationStatus)
                LabeledContent("Środowisko APNs", value: RemoteNotificationDiagnostics.apnsEnvironmentLabel())
                TextField("Notification server URL", text: $draftNotificationServerURL, axis: .vertical)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(.body, design: .monospaced))

                Text("Wpisz URL notifiera z MacBooka albo serwera, np. https://notify.example.com. Przed włączeniem alertów sprawdź https://notify.example.com/status. Powiadomienia live pozostają wyłączone, dopóki URL nie zostanie zapisany i iOS nie udzieli zgody.")
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
                    Label("Włącz alerty plików", systemImage: "bell.badge")
                }

                Toggle(isOn: $dailyWeatherAlertsEnabled) {
                    Label("Codzienna pogoda dla Wrocławia", systemImage: "cloud.sun")
                }

                Text("Gdy alerty live są włączone, Pavbot Notifier może wysyłać jeden polski briefing pogodowy codziennie o 07:30 Europe/Warsaw.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                LabeledContent("Token APNs", value: RemoteNotificationDiagnostics.deviceTokenPreview(for: remoteDeviceToken))

                if !deviceTokenRegisteredAt.isEmpty {
                    LabeledContent("Zarejestrowano", value: deviceTokenRegisteredAt)
                }

                if !remoteRegistrationError.isEmpty {
                    Label(remoteRegistrationError, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                Button {
                    UIPasteboard.general.string = remoteDeviceToken
                } label: {
                    Label("Kopiuj token APNs", systemImage: "doc.on.doc")
                }
                .accessibilityLabel("Kopiuj token APNs")
                .accessibilityHint("Kopiuje token urządzenia do Apple Push Notifications Console.")
                .disabled(remoteDeviceToken.isEmpty)

                Text("Użyj tego tokena w Apple Push Notifications Console. Wybierz Development dla buildów z Xcode i Production dla TestFlight.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Automatyzacje Codex") {
                NavigationLink {
                    AutomationListView()
                } label: {
                    Label("Otwórz automatyzacje", systemImage: "bolt.circle")
                }

                Text("Podgląd aktywnych workflow, ostatnich uruchomień i plików generowanych przez Codex. Główne wyniki są teraz w osobnych zakładkach aplikacji.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Diagnostyka i biblioteka") {
                NavigationLink {
                    ArtifactTimelineView()
                } label: {
                    Label("Otwórz wszystkie pliki", systemImage: "folder")
                }

                NavigationLink {
                    DiagnosticsView()
                } label: {
                    Label("Otwórz diagnostykę Codex", systemImage: "waveform.path.ecg")
                }
            }
        }
        .navigationTitle("Centrum połączeń")
        .onAppear {
            draftURL = store.manifestURLString
            draftNotificationServerURL = NotificationServerSettings.serverURLString
            manifestURLValidationMessage = ManifestURLValidator.validate(draftURL).message
            notificationServerValidationMessage = NotificationServerSettings.validationMessage(for: draftNotificationServerURL, required: false)
            dailyWeatherAlertsEnabled = DailyWeatherNotificationSettings.isEnabled()
            refreshRemoteNotificationDiagnostics()
            Task { await refreshNotificationStatus() }
            Task { await refreshNotificationServerReachability() }
        }
        .onChange(of: draftURL) { _, newValue in
            manifestURLValidationMessage = ManifestURLValidator.validate(newValue).message
        }
        .onChange(of: draftNotificationServerURL) { _, newValue in
            notificationServerValidationMessage = NotificationServerSettings.validationMessage(for: newValue, required: false)
        }
        .onChange(of: dailyWeatherAlertsEnabled) { _, newValue in
            DailyWeatherNotificationSettings.setEnabled(newValue)
            guard LiveNotificationSettings.isEnabled() else { return }
            Task {
                await RemoteNotificationPermission.refreshRegistrationIfNeeded()
                refreshRemoteNotificationDiagnostics()
            }
        }
    }

    private var hapticToggleBinding: Binding<Bool> {
        Binding(
            get: { haptics.isEnabled },
            set: { newValue in
                haptics.setEnabled(newValue)
                if newValue {
                    haptics.play(.success)
                }
            }
        )
    }

    private func saveManifestURL() {
        let trimmed = draftURL.trimmingCharacters(in: .whitespacesAndNewlines)
        switch ManifestURLValidator.validate(trimmed) {
        case .valid:
            manifestURLValidationMessage = nil
            store.manifestURLString = trimmed
            haptics.play(.success)
            Task { await store.reload() }
        case .invalid(let message):
            manifestURLValidationMessage = message
            haptics.play(.warning)
        }
    }

    private func restoreDefaultConnectionSettings() async {
        isRestoringDefaultConnectionSettings = true
        defaultConnectionSettingsStatus = "Pobieram domyślne ustawienia z Pavbot Notifier..."
        defer { isRestoringDefaultConnectionSettings = false }

        do {
            let defaults = try await AppDefaultsClient()
                .fetchDefaults(preferredServerURLString: draftNotificationServerURL)
            guard defaults.validationError == nil else {
                defaultConnectionSettingsStatus = defaults.validationError
                haptics.play(.warning)
                return
            }

            draftURL = defaults.manifestURL
            draftNotificationServerURL = defaults.notificationServerURL
            manifestURLValidationMessage = nil
            notificationServerValidationMessage = nil
            store.manifestURLString = defaults.manifestURL
            NotificationServerSettings.serverURLString = defaults.notificationServerURL
            defaultConnectionSettingsStatus = "Przywrócono domyślne połączenia."
            haptics.play(.success)

            await store.reload()
            await refreshNotificationServerReachability()
            refreshRemoteNotificationDiagnostics()
        } catch {
            defaultConnectionSettingsStatus = error.localizedDescription
            haptics.play(.error)
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
            haptics.play(.warning)
            return
        }

        NotificationServerSettings.serverURLString = trimmedServerURL
        LiveNotificationOnboarding.markPromptSeen()
        let granted = await RemoteNotificationPermission.requestAndRegister()
        LiveNotificationSettings.setEnabled(granted)
        haptics.play(granted ? .success : .warning)
        await refreshNotificationStatus()
        await refreshNotificationServerReachability()
        refreshRemoteNotificationDiagnostics()
    }

    private func refreshRemoteNotificationDiagnostics() {
        liveAlertsStatus = LiveNotificationSettings.isEnabled() ? "Włączone" : "Wyłączone"
        remoteDeviceToken = RemoteNotificationDiagnostics.deviceToken()
        remoteRegistrationError = RemoteNotificationDiagnostics.registrationError()
        deviceTokenRegistrationStatus = RemoteNotificationDiagnostics.registrationStatus()
        deviceTokenRegisteredAt = RemoteNotificationDiagnostics.lastRegisteredAt()
    }

    private func refreshNotificationServerReachability() async {
        guard notificationServerValidationMessage == nil, let serverURL = URL(string: draftNotificationServerURL.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            notificationServerReachability = draftNotificationServerURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Nie skonfigurowano" : "Niepoprawny URL"
            return
        }

        do {
            let statusURL = serverURL.appendingPathComponent("status")
            var request = URLRequest(url: statusURL)
            request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            request.timeoutInterval = 8
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                notificationServerReachability = "Niepoprawna odpowiedź"
                return
            }
            notificationServerReachability = (200..<300).contains(httpResponse.statusCode)
                ? "Dostępny"
                : "HTTP \(httpResponse.statusCode)"
        } catch {
            notificationServerReachability = PavbotUserFacingError.network(error, context: .notifier).message
        }
    }
}

private struct AccessibilityShowcaseCard: View {
    let feature: AccessibilityShowcaseFeature

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: feature.systemImage)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.blue)
                    .frame(width: 32, height: 32)
                    .background(Color.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(feature.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(feature.appStoreName)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                }
            }

            Text(feature.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.blue.opacity(0.14), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(feature.accessibilityLabel)
    }
}

private extension UNAuthorizationStatus {
    var label: String {
        switch self {
        case .notDetermined:
            "Nie pytano"
        case .denied:
            "Odmówiono"
        case .authorized:
            "Włączone"
        case .provisional:
            "Tymczasowe"
        case .ephemeral:
            "Sesyjne"
        @unknown default:
            "Nieznane"
        }
    }
}
