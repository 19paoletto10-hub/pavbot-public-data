import SwiftUI

@main
struct PavbotViewerApp: App {
    @UIApplicationDelegateAdaptor(PavbotRemoteNotificationAppDelegate.self) private var appDelegate
    @State private var store = ManifestStore()
    @State private var router = AppRouter()
    @State private var audioPlayback = AudioPlaybackService()
    @State private var weatherBrief = WeatherBriefStore(
        locationProvider: {
            try await WeatherLocationService().currentWeatherLocation()
        }
    )
    @State private var todayHumor = TodayHumorStore()
    @State private var appearance = AppAppearanceStore()
    private let notificationDelegate = ArtifactNotificationDelegate()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .environment(router)
                .environment(audioPlayback)
                .environment(weatherBrief)
                .environment(todayHumor)
                .environment(appearance)
                .preferredColorScheme(appearance.preference.preferredColorScheme)
                .onAppear {
                    notificationDelegate.install(router: router)
                }
                .onOpenURL { url in
                    router.handleOpenURL(url)
                    router.resolvePendingArtifact(in: store.manifest)
                }
        }
    }
}
