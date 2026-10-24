import AppKit
import SwiftUI

/// macOS grounds the window atmosphere in standard window chrome.
enum BrowserPlatformWindowAtmosphereStyle {
    static var backgroundColor: Color {
        Color(nsColor: .windowBackgroundColor)
    }
}
