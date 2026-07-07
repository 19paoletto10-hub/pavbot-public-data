import SwiftUI

struct ContentView: View {
    @Environment(ManifestStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(PavbotHaptics.self) private var haptics
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var showLiveNotificationPrompt = false

    var body: some View {
        Group {
            switch PavbotRootLayoutStyle.resolve(horizontalSizeClass: horizontalSizeClass) {
            case .tab:
                PavbotTabRootView()
            case .split:
                PavbotSplitRootView()
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            AudioPlaybackBanner()
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
            Text("Otrzymasz alert na iPhone, gdy GitHub wykryje nowe pliki automatyzacji Pavbot. Możesz zostawić to wyłączone i wrócić do ustawień później.")
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

    private func enableLiveNotificationsFromPrompt() {
        LiveNotificationOnboarding.markPromptSeen()
        if LiveNotificationOnboarding.needsSettingsBeforeSystemPrompt(serverURLString: NotificationServerSettings.serverURLString) {
            router.selectedTab = .settings
            return
        }

        Task {
            _ = await RemoteNotificationPermission.requestAndRegister()
        }
    }
}

private struct PavbotTabRootView: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        @Bindable var router = router

        TabView(selection: $router.selectedTab) {
            NavigationStack {
                WeatherBriefView()
            }
            .tabItem {
                Label(AppTab.today.displayTitle, systemImage: AppTab.today.systemImage)
            }
            .tag(AppTab.today)

            NavigationStack {
                PulseDayView()
            }
            .tabItem {
                Label(AppTab.pulseDay.displayTitle, systemImage: AppTab.pulseDay.systemImage)
            }
            .tag(AppTab.pulseDay)

            NavigationStack(path: $router.jobsPath) {
                JobsView()
            }
            .tabItem {
                Label(AppTab.jobs.displayTitle, systemImage: AppTab.jobs.systemImage)
            }
            .tag(AppTab.jobs)

            NavigationStack(path: $router.researchPath) {
                OverviewView()
            }
            .tabItem {
                Label(AppTab.research.displayTitle, systemImage: AppTab.research.systemImage)
            }
            .tag(AppTab.research)

            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label(AppTab.settings.displayTitle, systemImage: AppTab.settings.systemImage)
            }
            .tag(AppTab.settings)
        }
    }
}

private struct PavbotSplitRootView: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        NavigationSplitView {
            List(selection: selectedTabBinding) {
                Label(AppTab.today.displayTitle, systemImage: AppTab.today.systemImage)
                    .tag(AppTab.today)
                Label(AppTab.pulseDay.displayTitle, systemImage: AppTab.pulseDay.systemImage)
                    .tag(AppTab.pulseDay)
                Label(AppTab.jobs.displayTitle, systemImage: AppTab.jobs.systemImage)
                    .tag(AppTab.jobs)
                Label(AppTab.research.displayTitle, systemImage: AppTab.research.systemImage)
                    .tag(AppTab.research)
                Label(AppTab.settings.displayTitle, systemImage: AppTab.settings.systemImage)
                    .tag(AppTab.settings)
            }
            .navigationTitle("Pavbot")
        } detail: {
            detail
        }
    }

    private var selectedTabBinding: Binding<AppTab?> {
        Binding(
            get: { router.selectedTab },
            set: { newValue in
                if let newValue {
                    router.selectedTab = newValue
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
                    OverviewView()
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

private struct OverviewView: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        @Bindable var router = router

        VStack(spacing: 0) {
            Picker("Widok Przeglądu", selection: $router.selectedOverviewMode) {
                ForEach(OverviewMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .background(Color(.systemGroupedBackground))
            .accessibilityLabel("Widok Przeglądu")

            switch router.selectedOverviewMode {
            case .files:
                ArtifactTimelineView()
            case .reports:
                ResearchView()
            }
        }
    }
}

private struct AdaptiveDetailContainer<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(maxWidth: 1180, maxHeight: .infinity)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemGroupedBackground))
    }
}
