import SwiftUI

enum PavbotRootLayoutStyle: Equatable {
    case tab
    case split

    static func resolve(
        horizontalSizeClass: UserInterfaceSizeClass?,
        isRunningOnMac: Bool = ProcessInfo.processInfo.isiOSAppOnMac
    ) -> PavbotRootLayoutStyle {
        if isRunningOnMac {
            return .split
        }
        return horizontalSizeClass == .regular ? .split : .tab
    }
}
