import SwiftUI

@main
struct PavbotViewerApp: App {
    @UIApplicationDelegateAdaptor(PavbotRemoteNotificationAppDelegate.self) private var appDelegate
    @State private var store = ManifestStore()
    @State private var router = AppRouter()
    private let notificationDelegate = ArtifactNotificationDelegate()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .environment(router)
                .task {
                    notificationDelegate.install(router: router)
                }
        }
    }
}
