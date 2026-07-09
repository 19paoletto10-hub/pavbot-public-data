import SwiftUI

struct ContentView: View {
    @Environment(ManifestStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(PavbotHaptics.self) private var haptics
    @Environment(PavbotImagePreviewStore.self) private var imagePreviewStore
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var showLiveNotificationPrompt = false

    var body: some View {
        GeometryReader { proxy in
            let layoutStyle = PavbotRootLayoutStyle.resolve(
                horizontalSizeClass: horizontalSizeClass,
                width: proxy.size.width
            )

            rootContent(for: layoutStyle)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    AudioPlaybackBottomReserve(
                        layoutStyle: layoutStyle,
                        bottomSafeArea: proxy.safeAreaInsets.bottom
                    )
                }
                .overlay {
                    PavbotImagePreviewHost(imagePreviewStore: imagePreviewStore)
                }
                .overlay(alignment: .bottom) {
                    AudioPlaybackOverlayHost(
                        layoutStyle: layoutStyle,
                        bottomSafeArea: proxy.safeAreaInsets.bottom
                    )
                    .ignoresSafeArea(.keyboard, edges: .bottom)
                    .zIndex(AudioPlaybackBannerLayout.alwaysOnTopZIndex)
                }
        }
        .sensoryFeedback(.selection, trigger: router.selectedTab) { oldValue, newValue in
            oldValue != newValue && haptics.isEnabled
        }
        .task {
            await store.reload(minimumInterval: 60)
            store.startAutoRefreshLoop()
            Task {
                await RemoteNotificationPermission.refreshRegistrationIfNeeded()
            }
        }
        .onAppear {
            if LiveNotificationOnboarding.shouldPrompt() {
                showLiveNotificationPrompt = true
            }
        }
        .alert("Powiadomienia live", isPresented: $showLiveNotificationPrompt) {
            Button("Włącz") {
                enableLiveNotificationsFromPrompt()
            }
            Button("Nie teraz", role: .cancel) {
                LiveNotificationOnboarding.markPromptSeen()
            }
        } message: {
            Text("Otrzymasz alert na iPhone, gdy CloudKit opublikuje nowe briefingi Pavbot. Możesz zostawić to wyłączone i wrócić do ustawień później.")
        }
        .onChange(of: store.manifest) { _, _ in
            router.resolvePendingArtifact(in: store.manifest)
        }
        .onChange(of: router.pendingArtifactID) { _, _ in
            router.resolvePendingArtifact(in: store.manifest)
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            Task {
                await store.reload(minimumInterval: 60)
            }
            Task {
                await RemoteNotificationPermission.refreshRegistrationIfNeeded()
            }
        }
    }

    @ViewBuilder
    private func rootContent(for layoutStyle: PavbotRootLayoutStyle) -> some View {
        switch layoutStyle {
        case .tab:
            PavbotTabRootView()
        case .split:
            PavbotSplitRootView()
        }
    }

    private func enableLiveNotificationsFromPrompt() {
        LiveNotificationOnboarding.markPromptSeen()
        Task {
            _ = await RemoteNotificationPermission.requestAndRegister()
        }
    }
}

private struct AudioPlaybackBottomReserve: View {
    @Environment(PavbotAudioSessionCoordinator.self) private var audioCoordinator
    let layoutStyle: PavbotRootLayoutStyle
    let bottomSafeArea: CGFloat

    var body: some View {
        if audioCoordinator.currentSnapshot != nil {
            Color.clear
                .frame(height: AudioPlaybackBannerLayout.contentReserveHeight(for: layoutStyle, bottomSafeArea: bottomSafeArea))
                .allowsHitTesting(false)
        }
    }
}

private struct AudioPlaybackOverlayHost: View {
    @Environment(PavbotAudioSessionCoordinator.self) private var audioCoordinator
    let layoutStyle: PavbotRootLayoutStyle
    let bottomSafeArea: CGFloat

    var body: some View {
        if audioCoordinator.currentSnapshot != nil {
            AudioPlaybackBanner()
                .padding(.bottom, AudioPlaybackBannerLayout.bottomClearance(for: layoutStyle, bottomSafeArea: bottomSafeArea))
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(AudioPlaybackBannerLayout.alwaysOnTopZIndex)
        }
    }
}

private struct PavbotTabRootView: View {
    @Environment(AppRouter.self) private var router
    @Environment(AppLanguageStore.self) private var languageStore
    @State private var selectedVisibleTab: AppTab = .today

    var body: some View {
        @Bindable var router = router

        TabView(selection: selectedVisibleTabBinding) {
            NavigationStack {
                WeatherBriefView()
            }
            .tabItem {
                appTabLabel(title: AppTab.today.displayTitle(language: languageStore.preference), systemImage: AppTab.today.systemImage)
            }
            .tag(AppTab.today)

            NavigationStack {
                PulseDayView()
            }
            .tabItem {
                appTabLabel(title: AppTab.pulseDay.displayTitle(language: languageStore.preference), systemImage: AppTab.pulseDay.systemImage)
            }
            .tag(AppTab.pulseDay)

            NavigationStack(path: $router.jobsPath) {
                JobsView()
            }
            .tabItem {
                appTabLabel(title: AppTab.jobs.displayTitle(language: languageStore.preference), systemImage: AppTab.jobs.systemImage)
            }
            .tag(AppTab.jobs)

            NavigationStack(path: $router.researchPath) {
                ResearchView()
            }
            .tabItem {
                appTabLabel(title: AppTab.research.displayTitle(language: languageStore.preference), systemImage: AppTab.research.systemImage)
            }
            .tag(AppTab.research)

            NavigationStack(path: $router.artifactPath) {
                phoneSettingsTabContent
            }
            .tabItem {
                appTabLabel(title: AppTab.settings.displayTitle(language: languageStore.preference), systemImage: AppTab.settings.systemImage)
            }
            .tag(AppTab.settings)
        }
        .id("pavbot-tab-root-\(languageStore.preference.rawValue)")
        .onAppear {
            syncVisibleTabFromRouter()
        }
        .onChange(of: router.selectedTab) { _, _ in
            syncVisibleTabFromRouter()
        }
    }

    private var selectedVisibleTabBinding: Binding<AppTab> {
        Binding(
            get: { selectedVisibleTab },
            set: { newValue in
                selectedVisibleTab = newValue
                router.selectTabFromUser(newValue)
            }
        )
    }

    private func syncVisibleTabFromRouter() {
        let visibleTab = router.selectedTab.phoneVisibleTab
        if selectedVisibleTab != visibleTab {
            selectedVisibleTab = visibleTab
        }
    }

    @ViewBuilder
    private var phoneSettingsTabContent: some View {
        switch router.selectedTab {
        case .artifacts:
            ArtifactTimelineView()
        case .automations:
            AutomationListView(navigationMode: .embeddedInSettings)
        case .diagnostics:
            DiagnosticsView()
        default:
            SettingsView()
        }
    }

    private func appTabLabel(title: String, systemImage: String) -> some View {
        let localizedTitle = title
        return Label(localizedTitle, systemImage: systemImage)
    }
}

private extension AppTab {
    var phoneVisibleTab: AppTab {
        switch self {
        case .artifacts, .automations, .diagnostics:
            .settings
        default:
            self
        }
    }
}

private struct PavbotSplitRootView: View {
    @Environment(AppRouter.self) private var router
    @Environment(AppLanguageStore.self) private var languageStore

    var body: some View {
        NavigationSplitView {
            List(selection: selectedTabBinding) {
                appTabLabel(title: AppTab.today.displayTitle(language: languageStore.preference), systemImage: AppTab.today.systemImage)
                    .tag(AppTab.today)
                appTabLabel(title: AppTab.pulseDay.displayTitle(language: languageStore.preference), systemImage: AppTab.pulseDay.systemImage)
                    .tag(AppTab.pulseDay)
                appTabLabel(title: AppTab.jobs.displayTitle(language: languageStore.preference), systemImage: AppTab.jobs.systemImage)
                    .tag(AppTab.jobs)
                appTabLabel(title: AppTab.research.displayTitle(language: languageStore.preference), systemImage: AppTab.research.systemImage)
                    .tag(AppTab.research)
                appTabLabel(title: AppTab.settings.displayTitle(language: languageStore.preference), systemImage: AppTab.settings.systemImage)
                    .tag(AppTab.settings)
            }
            .id("pavbot-split-sidebar-\(languageStore.preference.rawValue)")
            .navigationTitle("Pavbot")
        } detail: {
            detail
        }
    }

    private func appTabLabel(title: String, systemImage: String) -> some View {
        let localizedTitle = title
        return Label(localizedTitle, systemImage: systemImage)
    }

    private var selectedTabBinding: Binding<AppTab?> {
        Binding(
            get: { router.selectedTab },
            set: { newValue in
                if let newValue {
                    router.selectTabFromUser(newValue)
                }
            }
        )
    }

    @ViewBuilder
    private var detail: some View {
        @Bindable var router = router

        switch router.selectedTab {
        case .automations:
            NavigationStack {
                AdaptiveDetailContainer {
                    AutomationListView()
                }
            }
        case .pulseDay:
            NavigationStack {
                AdaptiveDetailContainer {
                    PulseDayView()
                }
            }
        case .jobs:
            NavigationStack(path: $router.jobsPath) {
                AdaptiveDetailContainer {
                    JobsView()
                }
            }
        case .research:
            NavigationStack(path: $router.researchPath) {
                AdaptiveDetailContainer {
                    ResearchView()
                }
            }
        case .today:
            NavigationStack {
                AdaptiveDetailContainer {
                    WeatherBriefView()
                }
            }
        case .settings:
            NavigationStack {
                AdaptiveDetailContainer {
                    SettingsView()
                }
            }
        case .artifacts:
            NavigationStack(path: $router.artifactPath) {
                AdaptiveDetailContainer {
                    ArtifactTimelineView()
                }
            }
        case .diagnostics:
            NavigationStack {
                AdaptiveDetailContainer {
                    DiagnosticsView()
                }
            }
        }
    }
}

private struct AdaptiveDetailContainer<Content: View>: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @ViewBuilder var content: Content

    var body: some View {
        GeometryReader { proxy in
            let layout = PavbotAdaptiveLayout.resolve(
                width: proxy.size.width,
                horizontalSizeClass: horizontalSizeClass
            )

            content
                .frame(maxWidth: layout.contentMaxWidth, maxHeight: .infinity)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemGroupedBackground))
        }
    }
}
