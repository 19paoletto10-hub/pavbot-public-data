import SwiftUI

struct ContentView: View {
    @Environment(ManifestStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(\.scenePhase) private var scenePhase
    @State private var showLiveNotificationPrompt = false

    var body: some View {
        @Bindable var router = router

        TabView(selection: $router.selectedTab) {
            NavigationStack {
                AutomationListView()
            }
            .tabItem {
                Label("Automations", systemImage: "bolt.circle")
            }
            .tag(AppTab.automations)

            NavigationStack(path: $router.artifactPath) {
                ArtifactTimelineView()
            }
            .tabItem {
                Label("Artifacts", systemImage: "calendar")
            }
            .tag(AppTab.artifacts)

            NavigationStack {
                DiagnosticsView()
            }
            .tabItem {
                Label("Diagnostics", systemImage: "waveform.path.ecg")
            }
            .tag(AppTab.diagnostics)

            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape")
            }
            .tag(AppTab.settings)
        }
        .task {
            if store.manifest == nil {
                await store.load()
            }
            await store.startAutoRefreshLoop()
        }
        .onAppear {
            if LiveNotificationOnboarding.shouldPrompt() {
                showLiveNotificationPrompt = true
            }
        }
        .alert("Live notifications", isPresented: $showLiveNotificationPrompt) {
            Button("Enable") {
                enableLiveNotificationsFromPrompt()
            }
            Button("Not now", role: .cancel) {
                LiveNotificationOnboarding.markPromptSeen()
            }
        } message: {
            Text("Receive an iPhone alert when GitHub detects new Pavbot automation files. You can keep this off and enable it later in Settings.")
        }
        .onChange(of: store.manifest) { _, _ in
            router.resolvePendingArtifact(in: store.manifest)
        }
        .onChange(of: router.pendingArtifactID) { _, _ in
            router.resolvePendingArtifact(in: store.manifest)
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            Task { await store.reload() }
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
