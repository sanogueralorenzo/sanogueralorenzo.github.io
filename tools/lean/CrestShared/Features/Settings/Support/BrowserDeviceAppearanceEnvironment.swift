import SwiftUI

/// Shared monochrome tint for windows, menus and controls.
struct BrowserDeviceAppearanceEnvironment: ViewModifier {
    func body(content: Content) -> some View {
        content.tint(CrestBrandTheme.accent)
    }
}
