import Foundation
import Observation
import UIKit

enum PavbotHapticEvent: Equatable {
    case selection
    case lightImpact
    case success
    case warning
    case error
}

enum PavbotHapticPreference {
    static let storageKey = "pavbot.interactionHapticsEnabled"

    static func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        guard defaults.object(forKey: storageKey) != nil else { return true }
        return defaults.bool(forKey: storageKey)
    }

    static func save(_ isEnabled: Bool, in defaults: UserDefaults = .standard) {
        defaults.set(isEnabled, forKey: storageKey)
    }
}

protocol PavbotHapticGenerating {
    func play(_ event: PavbotHapticEvent)
}

final class UIKitPavbotHapticGenerator: PavbotHapticGenerating {
    func play(_ event: PavbotHapticEvent) {
        switch event {
        case .selection:
            UISelectionFeedbackGenerator().selectionChanged()
        case .lightImpact:
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case .success:
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .warning:
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        case .error:
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }
}

@MainActor
@Observable
final class PavbotHaptics {
    var isEnabled: Bool {
        didSet {
            PavbotHapticPreference.save(isEnabled, in: defaults)
        }
    }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let generator: PavbotHapticGenerating

    init(
        defaults: UserDefaults = .standard,
        generator: PavbotHapticGenerating = UIKitPavbotHapticGenerator()
    ) {
        self.defaults = defaults
        self.generator = generator
        self.isEnabled = PavbotHapticPreference.isEnabled(in: defaults)
    }

    func setEnabled(_ isEnabled: Bool) {
        self.isEnabled = isEnabled
    }

    func play(_ event: PavbotHapticEvent) {
        let currentPreference = PavbotHapticPreference.isEnabled(in: defaults)
        if currentPreference != isEnabled {
            isEnabled = currentPreference
        }
        guard currentPreference else { return }
        generator.play(event)
    }
}
