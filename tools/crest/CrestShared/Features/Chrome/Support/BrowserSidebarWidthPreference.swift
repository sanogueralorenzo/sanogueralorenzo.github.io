import CoreGraphics
import Foundation

enum BrowserSidebarWidthPreference {
    static func value(
        forKey key: String,
        default defaultWidth: CGFloat,
        defaults: UserDefaults = .standard
    ) -> CGFloat {
        guard defaults.object(forKey: key) != nil else {
            return BrowserChromeLayout.clampedSidebarWidth(defaultWidth)
        }
        return BrowserChromeLayout.clampedSidebarWidth(
            CGFloat(defaults.double(forKey: key))
        )
    }
}
