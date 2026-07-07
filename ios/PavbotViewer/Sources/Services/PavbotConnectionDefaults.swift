import Foundation

enum PavbotConnectionDefaults {
    static let manifestURLString = "https://raw.githubusercontent.com/19paoletto10-hub/pavbot-public-data/main/public/pavbot-manifest.json"
    static let cloudKitContainerIdentifier = "iCloud.com.paweltanski.pavbotviewer"

    static func enforceLegacyUserDefaults(_ defaults: UserDefaults = .standard) {
        defaults.set(manifestURLString, forKey: ManifestDefaults.urlDefaultsKey)
        defaults.removeObject(forKey: "pavbot.notificationServerURL")
    }
}
