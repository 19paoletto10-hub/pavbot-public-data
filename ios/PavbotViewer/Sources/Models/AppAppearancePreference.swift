import Foundation
import Observation
import SwiftUI

enum AppAppearancePreference: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    static let storageKey = "pavbot.appAppearancePreference"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system:
            "Auto"
        case .light:
            "Jasny"
        case .dark:
            "Ciemny"
        }
    }

    var preferredColorScheme: ColorScheme? {
        switch self {
        case .system:
            nil
        case .light:
            .light
        case .dark:
            .dark
        }
    }

    static func load(from defaults: UserDefaults = .standard) -> AppAppearancePreference {
        guard
            let rawValue = defaults.string(forKey: storageKey),
            let preference = AppAppearancePreference(rawValue: rawValue)
        else {
            return .system
        }
        return preference
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(rawValue, forKey: Self.storageKey)
    }
}

@Observable
final class AppAppearanceStore {
    var preference: AppAppearancePreference {
        didSet {
            preference.save(to: defaults)
        }
    }

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.preference = AppAppearancePreference.load(from: defaults)
    }
}
