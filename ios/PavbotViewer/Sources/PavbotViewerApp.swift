import SwiftUI

@main
struct PavbotViewerApp: App {
    @UIApplicationDelegateAdaptor(PavbotRemoteNotificationAppDelegate.self) private var appDelegate
    @State private var store: ManifestStore
    @State private var router = AppRouter()
    @State private var audioCoordinator: PavbotAudioSessionCoordinator
    @State private var audioPlayback: AudioPlaybackService
    @State private var weatherBrief = WeatherBriefStore(
        locationProvider: { mode in
            guard mode != .none else { return nil }
            return try await WeatherLocationService().currentWeatherLocation(mode: mode)
        }
    )
    @State private var todayHumor = TodayHumorStore()
    @State private var appearance = AppAppearanceStore()
    @State private var haptics = PavbotHaptics()
    @State private var imagePreview = PavbotImagePreviewStore()
    private let notificationDelegate = ArtifactNotificationDelegate()

    init() {
        let coordinator = PavbotAudioSessionCoordinator()
        let cloudKitService = CloudKitService.shared
        _store = State(initialValue: ManifestStore(briefingProvider: cloudKitService))
        _audioCoordinator = State(initialValue: coordinator)
        _audioPlayback = State(initialValue: AudioPlaybackService(audioCoordinator: coordinator))
        PavbotConnectionDefaults.enforceLegacyUserDefaults()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .environment(router)
                .environment(audioCoordinator)
                .environment(audioPlayback)
                .environment(weatherBrief)
                .environment(todayHumor)
                .environment(appearance)
                .environment(haptics)
                .environment(imagePreview)
                .preferredColorScheme(appearance.preference.preferredColorScheme)
                .onAppear {
                    notificationDelegate.install(router: router)
                    CloudKitPushRefreshCenter.shared.installRefreshHandler {
                        await store.reload(minimumInterval: 0)
                    }
                }
                .onOpenURL { url in
                    router.handleOpenURL(url)
                    router.resolvePendingArtifact(in: store.manifest)
                }
        }
    }
}
