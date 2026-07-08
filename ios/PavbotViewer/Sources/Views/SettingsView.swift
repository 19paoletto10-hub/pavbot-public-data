import AVFoundation
import CloudKit
import SwiftUI
import UIKit
import UserNotifications

struct SettingsView: View {
    @Environment(ManifestStore.self) private var store
    @Environment(AppAppearanceStore.self) private var appearanceStore
    @Environment(PavbotHaptics.self) private var haptics
    @State private var notificationStatus = "Nie sprawdzono"
    @State private var liveAlertsStatus = "Wyłączone"
    @State private var cloudKitReachability = "Nie sprawdzono"
    @State private var deviceTokenRegistrationStatus = "Nie zarejestrowano"
    @State private var deviceTokenRegisteredAt = ""
    @State private var remoteDeviceToken = ""
    @State private var remoteRegistrationError = ""
    @State private var dailyWeatherAlertsEnabled = true
    @State private var briefingNotificationMode = CloudKitBriefingNotificationMode.load()
    @State private var lastCloudKitPushSummary = "Brak"
    @State private var cloudKitStatusMessage: String?
    @State private var speechVoicePreference = SpeechVoiceSettings.load()
    @State private var speechVoiceCatalog = SpeechVoiceCatalog.current()
    @State private var speechVoiceStatusMessage: String?
    @StateObject private var speechVoicePreview = SpeechPlaybackService()

    var body: some View {
        GeometryReader { proxy in
            let layout = PavbotAdaptiveLayout.resolve(width: proxy.size.width, horizontalSizeClass: nil)

            Group {
                if layout.isPhone {
                    settingsPhoneDashboard(layout: layout)
                } else {
                    settingsDashboard(layout: layout)
                }
            }
            .environment(\.pavbotAdaptiveLayout, layout)
        }
        .navigationTitle("Centrum połączeń")
        .onAppear {
            cloudKitStatusMessage = nil
            dailyWeatherAlertsEnabled = DailyWeatherNotificationSettings.isEnabled()
            briefingNotificationMode = CloudKitBriefingNotificationMode.load()
            refreshSpeechVoiceSettings()
            refreshRemoteNotificationDiagnostics()
            Task { await refreshNotificationStatus() }
            Task { await refreshCloudKitReachability() }
        }
        .onReceive(NotificationCenter.default.publisher(for: AVSpeechSynthesizer.availableVoicesDidChangeNotification)) { _ in
            refreshSpeechVoiceSettings()
        }
        .onChange(of: dailyWeatherAlertsEnabled) { _, newValue in
            DailyWeatherNotificationSettings.setEnabled(newValue)
            guard LiveNotificationSettings.isEnabled() else { return }
            Task {
                await RemoteNotificationPermission.refreshRegistrationIfNeeded(mode: briefingNotificationMode)
                refreshRemoteNotificationDiagnostics()
            }
        }
        .onChange(of: briefingNotificationMode) { _, newValue in
            CloudKitBriefingNotificationMode.save(newValue)
            guard LiveNotificationSettings.isEnabled() else {
                refreshRemoteNotificationDiagnostics()
                return
            }
            Task {
                await RemoteNotificationPermission.refreshRegistrationIfNeeded(mode: newValue)
                refreshRemoteNotificationDiagnostics()
                haptics.play(remoteRegistrationError.isEmpty ? .success : .warning)
            }
        }
    }

    private func settingsPhoneDashboard(layout: PavbotAdaptiveLayout) -> some View {
        @Bindable var appearanceStore = appearanceStore

        return PavbotPremiumScreenScaffold(layout: layout) {
            PavbotCommandHero(
                eyebrow: "Centrum sterowania",
                title: "Centrum połączeń",
                subtitle: "Najważniejsze ustawienia, status połączeń i wejścia do biblioteki bez technicznych linków w interfejsie.",
                systemImage: "gearshape.2.fill",
                tint: .blue,
                insights: [
                    PavbotInsight(title: "Manifest", value: store.manifest == nil ? "Brak" : "OK", systemImage: "doc.badge.gearshape", tint: store.manifest == nil ? .orange : .green),
                    PavbotInsight(title: "Alerty", value: liveAlertsStatus, systemImage: "bell.badge.fill", tint: liveAlertsStatus == "Włączone" ? .green : .orange),
                    PavbotInsight(title: "CloudKit", value: cloudKitReachability, systemImage: "icloud.fill", tint: cloudKitReachability == "Dostępny" ? .green : .blue),
                    PavbotInsight(title: "APNs", value: deviceTokenRegistrationStatus, systemImage: "iphone.radiowaves.left.and.right", tint: remoteDeviceToken.isEmpty ? .orange : .green)
                ],
                footnote: "Publiczne metadane briefingów pochodzą z CloudKit, a pliki z opublikowanego manifestu GitHub."
            )

            PavbotReadingCard(title: "Wygląd", subtitle: "Motyw i komfort czytania", systemImage: "paintpalette.fill", tint: .blue) {
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

            PavbotReadingCard(title: "Dostępność i komfort", subtitle: "Haptyka oraz deklarowane funkcje dostępności", systemImage: "accessibility.fill", tint: .green) {
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

                LazyVGrid(columns: layout.adaptiveColumns(minimum: 230), spacing: 12) {
                    ForEach(AccessibilityShowcaseFeature.allCases) { feature in
                        AccessibilityShowcaseCard(feature: feature)
                    }
                }
                .padding(.vertical, 4)

                Label("Nie deklaruj opisów audio w v1, bo aplikacja nie ma osobnych opisów dla treści wizualnych.", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            PavbotReadingCard(title: "Połączenia Pavbot", subtitle: "Czytelny status bez surowych adresów URL", systemImage: "network", tint: .purple) {
                LabeledContent("Połączenia Pavbot", value: "Produkcyjne")
                LabeledContent("Manifest danych", value: store.manifest == nil ? "Niezaładowany" : "Załadowany")
                LabeledContent("CloudKit", value: PavbotConnectionDefaults.cloudKitContainerIdentifier)

                Text("Pavbot pobiera metadane briefingów z CloudKit, a opublikowane pliki z manifestu danych.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            PavbotReadingCard(title: "Powiadomienia", subtitle: "APNs, alerty live i codzienna pogoda", systemImage: "bell.badge.fill", tint: .orange) {
                LabeledContent("Status", value: notificationStatus)
                LabeledContent("Alerty live", value: liveAlertsStatus)
                LabeledContent("CloudKit", value: cloudKitReachability)
                LabeledContent("Token urządzenia", value: deviceTokenRegistrationStatus)
                LabeledContent("Środowisko APNs", value: RemoteNotificationDiagnostics.apnsEnvironmentLabel())

                briefingNotificationModeContent

                Text("Powiadomienia live przychodzą jako normalne alerty z dźwiękiem. Odświeżenie ponownie rejestruje alerty briefingów.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let cloudKitStatusMessage {
                    Label(cloudKitStatusMessage, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                Button {
                    Task { await requestNotifications() }
                } label: {
                    Label("Włącz / odśwież powiadomienia live", systemImage: "bell.badge")
                }

                Toggle(isOn: $dailyWeatherAlertsEnabled) {
                    Label("Codzienna pogoda dla Wrocławia", systemImage: "cloud.sun")
                }

                Text("Gdy alerty live są włączone, CloudKit wysyła widoczny alert i sygnał odświeżenia po publikacji gotowego briefingu.")
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

                Text("Użyj tego tokena w Apple Push Notifications Console. Wybierz Production dla tej kompilacji Pavbot.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            PavbotReadingCard(title: "Głos czytania", subtitle: "Natywny TTS i Personal Voice", systemImage: "speaker.wave.2.fill", tint: .purple) {
                speechVoiceSettingsContent
            }

            PavbotReadingCard(title: "Automatyzacje i pliki", subtitle: "Wejścia operacyjne bez opuszczania Ustawień", systemImage: "bolt.circle.fill", tint: .yellow) {
                NavigationLink {
                    AutomationListView(navigationMode: .embeddedInSettings)
                } label: {
                    PavbotCompactStoryRow(
                        title: "Otwórz automatyzacje",
                        subtitle: "Aktywne przepływy, statusy i ostatnie uruchomienia.",
                        systemImage: "bolt.circle",
                        tint: .yellow
                    )
                }
                .buttonStyle(.plain)

                NavigationLink {
                    ArtifactTimelineView(navigationMode: .embeddedInSettings)
                } label: {
                    PavbotCompactStoryRow(
                        title: "Otwórz wszystkie pliki",
                        subtitle: "Biblioteka artefaktów z wyborem automatyzacji w tym samym ekranie.",
                        systemImage: "folder",
                        tint: .blue
                    )
                }
                .buttonStyle(.plain)

                NavigationLink {
                    DiagnosticsView()
                } label: {
                    PavbotCompactStoryRow(
                        title: "Otwórz diagnostykę Codex",
                        subtitle: "Zdrowie manifestu, automatyzacji i powiadomień.",
                        systemImage: "waveform.path.ecg",
                        tint: .red
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func settingsDashboard(layout: PavbotAdaptiveLayout) -> some View {
        @Bindable var appearanceStore = appearanceStore

        return PavbotPremiumScreenScaffold(layout: layout) {
                PavbotCommandHero(
                    eyebrow: "Centrum sterowania",
                    title: "Centrum połączeń",
                    subtitle: layout.usesDashboardLayout
                        ? "Status połączeń, powiadomień i automatyzacji w układzie czytelnym dla dużego okna."
                        : "Najważniejsze ustawienia i statusy w kompaktowym centrum sterowania.",
                    systemImage: "gearshape.2.fill",
                    tint: .blue,
                    insights: [
                        PavbotInsight(title: "Manifest", value: store.manifest == nil ? "Brak" : "OK", systemImage: "doc.badge.gearshape", tint: store.manifest == nil ? .orange : .green),
                        PavbotInsight(title: "Alerty", value: liveAlertsStatus, systemImage: "bell.badge.fill", tint: liveAlertsStatus == "Włączone" ? .green : .orange),
                        PavbotInsight(title: "CloudKit", value: cloudKitReachability, systemImage: "icloud.fill", tint: cloudKitReachability == "Dostępny" ? .green : .blue),
                        PavbotInsight(title: "APNs", value: deviceTokenRegistrationStatus, systemImage: "iphone.radiowaves.left.and.right", tint: remoteDeviceToken.isEmpty ? .orange : .green)
                    ]
                )

                LazyVGrid(columns: layout.adaptiveColumns(minimum: 320), spacing: layout.cardSpacing) {
                    SettingsDashboardCard(title: "Wygląd", subtitle: "Motyw i komfort czytania", systemImage: "paintpalette.fill", tint: .blue) {
                        Picker("Motyw aplikacji", selection: $appearanceStore.preference) {
                            ForEach(AppAppearancePreference.allCases) { preference in
                                Text(preference.title).tag(preference)
                            }
                        }
                        .pickerStyle(.segmented)

                        Text("Auto używa ustawień systemu iOS. Jasny oraz Ciemny wymuszają wygląd tylko w Pavbot.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    SettingsDashboardCard(title: "Dostępność", subtitle: "Haptyka i realne funkcje dostępności", systemImage: "accessibility.fill", tint: .green) {
                        Toggle(isOn: hapticToggleBinding) {
                            Label("Dotyk interakcji", systemImage: "hand.tap.fill")
                        }

                        LazyVGrid(columns: layout.adaptiveColumns(minimum: 220), spacing: 12) {
                            ForEach(AccessibilityShowcaseFeature.allCases) { feature in
                                AccessibilityShowcaseCard(feature: feature)
                            }
                        }

                        Label("Nie deklaruj opisów audio w v1, bo aplikacja nie ma osobnych opisów dla treści wizualnych.", systemImage: "info.circle")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    SettingsDashboardCard(title: "Połączenia", subtitle: "Produkcja i manifest danych", systemImage: "network", tint: .purple) {
                        LabeledContent("Połączenia Pavbot", value: "Produkcyjne")
                        LabeledContent("Manifest danych", value: store.manifest == nil ? "Niezaładowany" : "Załadowany")
                        LabeledContent("CloudKit", value: PavbotConnectionDefaults.cloudKitContainerIdentifier)
                        Text("CloudKit jest źródłem metadanych i alertów, a manifest danych pozostaje źródłem opublikowanych plików.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }

                    SettingsDashboardCard(title: "Powiadomienia", subtitle: "APNs i codzienna pogoda", systemImage: "bell.badge.fill", tint: .orange) {
                        LabeledContent("Status", value: notificationStatus)
                        LabeledContent("Alerty live", value: liveAlertsStatus)
                        LabeledContent("CloudKit", value: cloudKitReachability)
                        LabeledContent("Token urządzenia", value: deviceTokenRegistrationStatus)
                        LabeledContent("Środowisko APNs", value: RemoteNotificationDiagnostics.apnsEnvironmentLabel())

                        briefingNotificationModeContent

                        if let cloudKitStatusMessage {
                            Label(cloudKitStatusMessage, systemImage: "exclamationmark.triangle")
                                .font(.callout)
                                .foregroundStyle(.orange)
                        }

                        Button {
                            Task { await requestNotifications() }
                        } label: {
                            Label("Włącz / odśwież powiadomienia live", systemImage: "bell.badge")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)

                        Toggle(isOn: $dailyWeatherAlertsEnabled) {
                            Label("Codzienna pogoda dla Wrocławia", systemImage: "cloud.sun")
                        }

                        LabeledContent("Token APNs", value: RemoteNotificationDiagnostics.deviceTokenPreview(for: remoteDeviceToken))

                        if !deviceTokenRegisteredAt.isEmpty {
                            LabeledContent("Zarejestrowano", value: deviceTokenRegisteredAt)
                        }

                        if !remoteRegistrationError.isEmpty {
                            Label(remoteRegistrationError, systemImage: "exclamationmark.triangle")
                                .font(.callout)
                                .foregroundStyle(.orange)
                        }

                        Button {
                            UIPasteboard.general.string = remoteDeviceToken
                        } label: {
                            Label("Kopiuj token APNs", systemImage: "doc.on.doc")
                                .frame(maxWidth: .infinity)
                        }
                            .buttonStyle(.bordered)
                            .disabled(remoteDeviceToken.isEmpty)
                    }

                    SettingsDashboardCard(title: "Głos czytania", subtitle: "Natywny TTS i Personal Voice", systemImage: "speaker.wave.2.fill", tint: .purple) {
                        speechVoiceSettingsContent
                    }

                    SettingsDashboardCard(title: "Automatyzacje", subtitle: "Przepływy i pliki Codex", systemImage: "bolt.circle.fill", tint: .yellow) {
                        NavigationLink {
                            AutomationListView(navigationMode: .embeddedInSettings)
                        } label: {
                            PavbotActionRow(title: "Otwórz automatyzacje", subtitle: "Aktywne przepływy, ostatnie uruchomienia i statusy.", systemImage: "bolt.circle", tint: .yellow)
                        }

                        NavigationLink {
                            ArtifactTimelineView(navigationMode: .embeddedInSettings)
                        } label: {
                            PavbotActionRow(title: "Otwórz wszystkie pliki", subtitle: "Biblioteka artefaktów bez przełączania z Ustawień do zakładki Dzisiaj.", systemImage: "folder", tint: .blue)
                        }
                    }

                    SettingsDashboardCard(title: "Diagnostyka", subtitle: "Stan zdrowia aplikacji", systemImage: "waveform.path.ecg", tint: .red) {
                        NavigationLink {
                            DiagnosticsView()
                        } label: {
                            PavbotActionRow(title: "Otwórz diagnostykę Codex", subtitle: "Status manifestu, automatyzacji i połączeń bez podglądu raw manifestu.", systemImage: "waveform.path.ecg", tint: .red)
                        }
                    }
                }
        }
    }

    @ViewBuilder
    private var briefingNotificationModeContent: some View {
        LabeledContent("Tryb briefingów", value: briefingNotificationMode.title)

        Picker("Tryb briefingów", selection: $briefingNotificationMode) {
            ForEach(CloudKitBriefingNotificationMode.allCases) { mode in
                Text(mode.title).tag(mode)
            }
        }
        .pickerStyle(.segmented)

        Text(briefingNotificationMode.detail)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

        VStack(alignment: .leading, spacing: 4) {
            Text("Ostatni push CloudKit")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(lastCloudKitPushSummary)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var speechVoiceSettingsContent: some View {
        Text("Pavbot nie nagrywa próbki głosu. Personal Voice pochodzi z ustawień iOS i jest używany tylko po Twojej zgodzie.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

        Picker("Tryb głosu", selection: speechVoiceModeBinding) {
            ForEach(SpeechVoiceMode.allCases) { mode in
                Text(mode.title).tag(mode)
            }
        }
        .pickerStyle(.segmented)

        switch speechVoicePreference.mode {
        case .polishDefault:
            LabeledContent("Aktywny głos", value: speechVoiceCatalog.defaultSystemVoice?.displayTitle ?? "pl-PL")
        case .selectedVoice:
            if speechVoiceCatalog.systemVoices.isEmpty {
                Label("Brak dostępnych głosów systemowych. Pavbot spróbuje użyć pl-PL.", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else {
                Picker("Głos systemowy", selection: systemVoiceIdentifierBinding) {
                    ForEach(speechVoiceCatalog.systemVoices) { voice in
                        Text("\(voice.displayTitle) · \(voice.displaySubtitle)").tag(voice.id)
                    }
                }
                .pickerStyle(.menu)
            }
        case .personalVoice:
            LabeledContent("Status Personal Voice", value: speechVoiceCatalog.personalVoiceStatusLabel)

            if speechVoiceCatalog.personalVoiceAuthorization != .authorized {
                Button {
                    requestPersonalVoiceAuthorization()
                } label: {
                    Label("Zezwól na Personal Voice", systemImage: "person.wave.2.fill")
                }
                .buttonStyle(.borderedProminent)
            }

            if speechVoiceCatalog.personalVoices.isEmpty {
                Text("Jeśli nie widzisz własnego głosu, utwórz go w Ustawieniach iOS > Dostępność > Personal Voice, a potem odśwież listę.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Picker("Personal Voice", selection: personalVoiceIdentifierBinding) {
                    ForEach(speechVoiceCatalog.personalVoices) { voice in
                        Text("\(voice.displayTitle) · \(voice.displaySubtitle)").tag(voice.id)
                    }
                }
                .pickerStyle(.menu)
            }
        }

        if let speechVoiceStatusMessage {
            Label(speechVoiceStatusMessage, systemImage: "info.circle")
                .font(.caption)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        }

        if let errorMessage = speechVoicePreview.errorMessage {
            Label(errorMessage, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        }

        HStack(spacing: 10) {
            Button {
                refreshSpeechVoiceSettings()
            } label: {
                Label("Odśwież głosy", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)

            Button {
                testSpeechVoice()
            } label: {
                Label("Testuj głos", systemImage: "speaker.wave.2.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var speechVoiceModeBinding: Binding<SpeechVoiceMode> {
        Binding(
            get: { speechVoicePreference.mode },
            set: { mode in
                switch mode {
                case .polishDefault:
                    setSpeechVoicePreference(.polishDefault)
                case .selectedVoice:
                    setSpeechVoicePreference(
                        SpeechVoicePreference(
                            mode: .selectedVoice,
                            voiceIdentifier: speechVoiceCatalog.defaultSystemVoice?.id
                        )
                    )
                case .personalVoice:
                    setSpeechVoicePreference(
                        SpeechVoicePreference(
                            mode: .personalVoice,
                            voiceIdentifier: speechVoiceCatalog.personalVoices.first?.id
                        )
                    )
                }
            }
        )
    }

    private var systemVoiceIdentifierBinding: Binding<String> {
        Binding(
            get: {
                if let identifier = speechVoicePreference.voiceIdentifier,
                   speechVoiceCatalog.systemVoices.contains(where: { $0.id == identifier }) {
                    return identifier
                }
                return speechVoiceCatalog.defaultSystemVoice?.id ?? ""
            },
            set: { identifier in
                setSpeechVoicePreference(SpeechVoicePreference(mode: .selectedVoice, voiceIdentifier: identifier))
            }
        )
    }

    private var personalVoiceIdentifierBinding: Binding<String> {
        Binding(
            get: {
                if let identifier = speechVoicePreference.voiceIdentifier,
                   speechVoiceCatalog.personalVoices.contains(where: { $0.id == identifier }) {
                    return identifier
                }
                return speechVoiceCatalog.personalVoices.first?.id ?? ""
            },
            set: { identifier in
                setSpeechVoicePreference(SpeechVoicePreference(mode: .personalVoice, voiceIdentifier: identifier))
            }
        )
    }

    private func refreshSpeechVoiceSettings() {
        speechVoiceCatalog = SpeechVoiceCatalog.current()
        speechVoicePreference = SpeechVoiceSettings.load()
        speechVoiceStatusMessage = speechVoiceCatalog.fallbackMessage(for: speechVoicePreference)
    }

    private func setSpeechVoicePreference(_ preference: SpeechVoicePreference) {
        speechVoicePreference = preference
        SpeechVoiceSettings.save(preference)
        speechVoiceStatusMessage = speechVoiceCatalog.fallbackMessage(for: preference)
        haptics.play(.selection)
    }

    private func requestPersonalVoiceAuthorization() {
        Task {
            _ = await SpeechVoiceCatalog.requestPersonalVoiceAuthorization()
            refreshSpeechVoiceSettings()
            haptics.play(speechVoiceCatalog.personalVoiceAuthorization == .authorized ? .success : .warning)
        }
    }

    private func testSpeechVoice() {
        haptics.play(.selection)
        speechVoicePreview.start(
            itemID: "settings-tts-preview",
            title: "Test głosu",
            text: "Pavbot będzie czytać newsy tym głosem. Domyślnie używam stabilnego polskiego TTS."
        )
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
        LiveNotificationOnboarding.markPromptSeen()
        let granted = await RemoteNotificationPermission.requestAndRegister(mode: briefingNotificationMode)
        cloudKitStatusMessage = granted ? nil : RemoteNotificationDiagnostics.registrationError()
        LiveNotificationSettings.setEnabled(granted)
        haptics.play(granted ? .success : .warning)
        await refreshNotificationStatus()
        await refreshCloudKitReachability()
        refreshRemoteNotificationDiagnostics()
    }

    private func refreshRemoteNotificationDiagnostics() {
        liveAlertsStatus = LiveNotificationSettings.isEnabled() ? "Włączone" : "Wyłączone"
        remoteDeviceToken = RemoteNotificationDiagnostics.deviceToken()
        remoteRegistrationError = RemoteNotificationDiagnostics.registrationError()
        deviceTokenRegistrationStatus = RemoteNotificationDiagnostics.registrationStatus()
        deviceTokenRegisteredAt = RemoteNotificationDiagnostics.lastRegisteredAt()
        lastCloudKitPushSummary = RemoteNotificationDiagnostics.lastCloudKitPushSummary()
    }

    private func refreshCloudKitReachability() async {
        do {
            let status = try await cloudKitAccountStatus()
            cloudKitReachability = status.pavbotLabel
            cloudKitStatusMessage = status == .available ? nil : "CloudKit nie jest dostępny dla tego konta iCloud: \(status.pavbotLabel)."
        } catch {
            cloudKitReachability = "Błąd"
            cloudKitStatusMessage = PavbotUserFacingError.network(error, context: .manifest).message
        }
    }

    private func cloudKitAccountStatus() async throws -> CKAccountStatus {
        let container = CKContainer(identifier: PavbotConnectionDefaults.cloudKitContainerIdentifier)
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CKAccountStatus, Error>) in
            container.accountStatus { status, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: status)
                }
            }
        }
    }
}

private extension CKAccountStatus {
    var pavbotLabel: String {
        switch self {
        case .available:
            "Dostępny"
        case .noAccount:
            "Brak iCloud"
        case .restricted:
            "Ograniczony"
        case .couldNotDetermine:
            "Nieustalony"
        case .temporarilyUnavailable:
            "Chwilowo niedostępny"
        @unknown default:
            "Nieznany"
        }
    }
}

private struct SettingsDashboardCard<Content: View>: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: systemImage)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: 46, height: 46)
                    .background(tint.opacity(0.13), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.title3.weight(.bold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                content()
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(tint.opacity(0.12), lineWidth: 1)
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
