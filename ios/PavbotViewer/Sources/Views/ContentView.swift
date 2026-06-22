import SwiftUI

struct ContentView: View {
    @Environment(ManifestStore.self) private var store
    @Environment(AppRouter.self) private var router

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
        }
        .onChange(of: store.manifest) { _, _ in
            router.resolvePendingArtifact(in: store.manifest)
        }
        .onChange(of: router.pendingArtifactID) { _, _ in
            router.resolvePendingArtifact(in: store.manifest)
        }
    }
}
