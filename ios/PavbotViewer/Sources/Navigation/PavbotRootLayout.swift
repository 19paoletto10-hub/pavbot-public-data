import SwiftUI

enum PavbotRootLayoutStyle: Equatable {
    case tab
    case split

    static func resolve(
        horizontalSizeClass: UserInterfaceSizeClass?,
        width: CGFloat? = nil,
        isRunningOnMac: Bool = ProcessInfo.processInfo.isiOSAppOnMac
    ) -> PavbotRootLayoutStyle {
        let viewport = PavbotViewportClass.resolve(
            width: width,
            horizontalSizeClass: horizontalSizeClass,
            isRunningOnMac: isRunningOnMac
        )
        if viewport != .phone {
            return .split
        }
        return .tab
    }
}
