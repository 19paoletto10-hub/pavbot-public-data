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

    private func settingsPhoneDashboard(layout: PavbotAdaptiveLayout) -> some View {
        @Bindable var appearanceStore = appearanceStore

        return PavbotPremiumScreenScaffold(layout: layout) {
            PavbotCommandHero(
                eyebrow: "Control Center",
                title: "Centrum połączeń",
                subtitle: "Najważniejsze ustawienia, status połączeń i wejścia do biblioteki bez technicznych linków w interfejsie.",
                systemImage: "gearshape.2.fill",
                tint: .blue,
                insights: [
                    PavbotInsight(title: "Manifest", value: store.manifest == nil ? "Brak" : "OK", systemImage: "doc.badge.gearshape", tint: store.manifest == nil ? .orange : .green),
                    PavbotInsight(title: "Alerty", value: liveAlertsStatus, systemImage: "bell.badge.fill", tint: liveAlertsStatus == "Włączone" ? .green : .orange),
                    PavbotInsight(title: "Notifier", value: notificationServerReachability, systemImage: "antenna.radiowaves.left.and.right", tint: notificationServerReachability == "Dostępny" ? .green : .blue),
                    PavbotInsight(title: "APNs", value: deviceTokenRegistrationStatus, systemImage: "iphone.radiowaves.left.and.right", tint: remoteDeviceToken.isEmpty ? .orange : .green)
                ],
                footnote: "Adresy produkcyjne są ukryte w UI; aplikacja nadal używa ich w konfiguracji i diagnostyce."
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

                Label("Nie deklaruj Audio Descriptions w v1, bo aplikacja nie ma osobnych opisów audio dla treści wizualnych.", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            PavbotReadingCard(title: "Połączenia Pavbot", subtitle: "Czytelny status bez raw URL-i", systemImage: "network", tint: .purple) {
                LabeledContent("Połączenia Pavbot", value: "Produkcyjne")
                LabeledContent("Manifest danych", value: store.manifest == nil ? "Niezaładowany" : "Załadowany")
                LabeledContent("Serwer powiadomień", value: "Produkcyjny")

                Text("Pavbot używa produkcyjnych adresów połączeń. Pola są tylko do odczytu, żeby aplikacja zawsze pobierała właściwe dane.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            PavbotReadingCard(title: "Powiadomienia", subtitle: "APNs, alerty live i codzienna pogoda", systemImage: "bell.badge.fill", tint: .orange) {
                LabeledContent("Status", value: notificationStatus)
                LabeledContent("Alerty live", value: liveAlertsStatus)
                LabeledContent("Serwer dostępny", value: notificationServerReachability)
                LabeledContent("Token urządzenia", value: deviceTokenRegistrationStatus)
                LabeledContent("Środowisko APNs", value: RemoteNotificationDiagnostics.apnsEnvironmentLabel())

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

            PavbotReadingCard(title: "Automatyzacje i pliki", subtitle: "Wejścia operacyjne bez opuszczania Ustawień", systemImage: "bolt.circle.fill", tint: .yellow) {
                NavigationLink {
                    AutomationListView(navigationMode: .embeddedInSettings)
                } label: {
                    PavbotCompactStoryRow(
                        title: "Otwórz automatyzacje",
                        subtitle: "Aktywne workflow, statusy i ostatnie uruchomienia.",
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
                    eyebrow: "Control Center",
                    title: "Centrum połączeń",
                    subtitle: layout.usesDashboardLayout
                        ? "Status połączeń, powiadomień i automatyzacji w układzie czytelnym dla dużego okna."
                        : "Najważniejsze ustawienia i statusy w kompaktowym control center.",
                    systemImage: "gearshape.2.fill",
                    tint: .blue,
                    insights: [
                        PavbotInsight(title: "Manifest", value: store.manifest == nil ? "Brak" : "OK", systemImage: "doc.badge.gearshape", tint: store.manifest == nil ? .orange : .green),
                        PavbotInsight(title: "Alerty", value: liveAlertsStatus, systemImage: "bell.badge.fill", tint: liveAlertsStatus == "Włączone" ? .green : .orange),
                        PavbotInsight(title: "Notifier", value: notificationServerReachability, systemImage: "antenna.radiowaves.left.and.right", tint: notificationServerReachability == "Dostępny" ? .green : .blue),
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

                        Label("Nie deklaruj Audio Descriptions w v1, bo aplikacja nie ma osobnych opisów audio dla treści wizualnych.", systemImage: "info.circle")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    SettingsDashboardCard(title: "Połączenia", subtitle: "Produkcja i manifest danych", systemImage: "network", tint: .purple) {
                        LabeledContent("Połączenia Pavbot", value: "Produkcyjne")
                        LabeledContent("Manifest danych", value: store.manifest == nil ? "Niezaładowany" : "Załadowany")
                        LabeledContent("Serwer powiadomień", value: "Produkcyjny")
                        Text("Adresy są ukryte w UI, ale konfiguracja dalej używa produkcyjnych endpointów aplikacji.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }

                    SettingsDashboardCard(title: "Powiadomienia", subtitle: "APNs i codzienna pogoda", systemImage: "bell.badge.fill", tint: .orange) {
                        LabeledContent("Status", value: notificationStatus)
                        LabeledContent("Alerty live", value: liveAlertsStatus)
                        LabeledContent("Serwer dostępny", value: notificationServerReachability)
                        LabeledContent("Token urządzenia", value: deviceTokenRegistrationStatus)
                        LabeledContent("Środowisko APNs", value: RemoteNotificationDiagnostics.apnsEnvironmentLabel())

                        if let notificationServerValidationMessage {
                            Label(notificationServerValidationMessage, systemImage: "exclamationmark.triangle")
                                .font(.callout)
                                .foregroundStyle(.orange)
                        }

                        Button {
                            Task { await requestNotifications() }
                        } label: {
                            Label("Włącz alerty plików", systemImage: "bell.badge")
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

                    SettingsDashboardCard(title: "Automatyzacje", subtitle: "Workflow i pliki Codex", systemImage: "bolt.circle.fill", tint: .yellow) {
                        NavigationLink {
                            AutomationListView(navigationMode: .embeddedInSettings)
                        } label: {
                            PavbotActionRow(title: "Otwórz automatyzacje", subtitle: "Aktywne workflow, ostatnie uruchomienia i statusy.", systemImage: "bolt.circle", tint: .yellow)
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
