import SwiftUI

/// Hands the device's appearance choices that design-system components read
/// to everything under a window root, and follows them as they change.
struct BrowserDeviceAppearanceEnvironment: ViewModifier {
    private var appearance: BrowserDeviceAppearanceStore { .shared }

    func body(content: Content) -> some View {
        content.environment(\.crestSurfaceMaterial, appearance.surfaceMaterial)
    }
}
