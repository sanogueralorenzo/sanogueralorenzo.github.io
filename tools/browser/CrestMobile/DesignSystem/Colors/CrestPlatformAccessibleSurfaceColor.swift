import SwiftUI
import UIKit

/// The opaque iOS fallback used when Reduce Transparency is enabled.
enum CrestPlatformAccessibleSurfaceColor {
    static var background: Color {
        Color(uiColor: .systemBackground)
    }
}
