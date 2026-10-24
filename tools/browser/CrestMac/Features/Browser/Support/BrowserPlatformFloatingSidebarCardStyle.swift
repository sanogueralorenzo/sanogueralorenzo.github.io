import AppKit
import SwiftUI

/// macOS grounds the floating sidebar card in standard window chrome.
enum BrowserPlatformFloatingSidebarCardStyle {
    static var backgroundColor: Color {
        Color(nsColor: .windowBackgroundColor)
    }
}
