import SwiftUI
import UIKit
import UserNotifications

struct SettingsView: View {
    @Environment(ManifestStore.self) private var store
    @Environment(AppAppearanceStore.self) private var appearanceStore
    @Environment(PavbotHaptics.self) private var haptics
    @State private var notificationStatus = "Nie sprawdzono"
    @State private var liveAlertsStatus = "Wyłączone"
    @State private var notificationServerReachability = "Nie sprawdzono"
    @State private var deviceTokenRegistrationStatus = "Nie zarejestrowano"
    @State private var deviceTokenRegisteredAt = ""
    @State private var remoteDeviceToken = ""
    @State private var remoteRegistrationError = ""
    @State private var dailyWeatherAlertsEnabled = true
    @State private var notificationServerValidationMessage: String?

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
                Text("Pavbot używa produkcyjnych adresów połączeń. Pola są tylko do odczytu, żeby aplikacja zawsze pobierała właściwe dane.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Manifest") {
                TextField("Manifest URL", text: .constant(PavbotConnectionDefaults.manifestURLString), axis: .vertical)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(.body, design: .monospaced))
                    .disabled(true)
                    .accessibilityHint("Pole tylko do odczytu.")

                Text("To produkcyjny public GitHub raw manifest URL Pavbot.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                TextField("Notification server URL", text: .constant(PavbotConnectionDefaults.notificationServerURLString), axis: .vertical)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(.body, design: .monospaced))
                    .disabled(true)
                    .accessibilityHint("Pole tylko do odczytu.")

                Text("Powiadomienia live korzystają z produkcyjnego Pavbot Notifier. Alerty wymagają zgody iOS.")
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
            notificationServerValidationMessage = NotificationServerSettings.validationMessage(for: NotificationServerSettings.serverURLString, required: true)
            dailyWeatherAlertsEnabled = DailyWeatherNotificationSettings.isEnabled()
            refreshRemoteNotificationDiagnostics()
            Task { await refreshNotificationStatus() }
            Task { await refreshNotificationServerReachability() }
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

    private func refreshNotificationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationStatus = settings.authorizationStatus.label
    }

    private func requestNotifications() async {
        if let message = NotificationServerSettings.validationMessage(for: NotificationServerSettings.serverURLString, required: true) {
            notificationServerValidationMessage = message
            haptics.play(.warning)
            return
        }

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
        guard notificationServerValidationMessage == nil else {
            notificationServerReachability = "Niepoprawny URL"
            return
        }

        do {
            var request = URLRequest(url: PavbotConnectionDefaults.statusURL)
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
