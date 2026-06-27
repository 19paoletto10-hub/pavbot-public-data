import Foundation

enum PavbotConnectionDefaults {
    static let manifestURLString = "https://raw.githubusercontent.com/19paoletto10-hub/pavbot-public-data/main/public/pavbot-manifest.json"
    static let notificationServerURLString = "https://notify.paweltanski.com"
    static let statusURLString = "https://notify.paweltanski.com/status"

    static var notificationServerURL: URL {
        URL(string: notificationServerURLString)!
    }

    static var statusURL: URL {
        URL(string: statusURLString)!
    }

    static func enforceLegacyUserDefaults(_ defaults: UserDefaults = .standard) {
        defaults.set(manifestURLString, forKey: ManifestDefaults.urlDefaultsKey)
        defaults.set(notificationServerURLString, forKey: NotificationServerSettings.urlDefaultsKey)
    }
}
