import AppKit
import SwiftUI

/// The opaque macOS fallback used when Reduce Transparency is enabled.
enum CrestPlatformAccessibleSurfaceColor {
    static var background: Color {
        Color(nsColor: .windowBackgroundColor)
    }
}
