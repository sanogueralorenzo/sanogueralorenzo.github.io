import SwiftUI

/// Supplies the window's own corner at the scene boundary. The device's border
/// and sidebar side reach the views that draw them from
/// ``BrowserDeviceAppearanceStore``, so changing them never changes a window's
/// environment.
struct BrowserChromeAppearancePersistence: ViewModifier {
    /// The corner radius of the window this scene fills, which the page frame
    /// follows on Mac.
    @State private var windowCornerRadius: CGFloat?
    @State private var isWindowFullScreen = false

    func body(content: Content) -> some View {
        content
            .environment(\.browserWindowCornerRadius, isWindowFullScreen ? nil : windowCornerRadius)
            #if os(macOS)
                // The window's corners change shape with its chrome, so the
                // radius is read live rather than assumed.
                .onGeometryChange(for: CGFloat?.self) { proxy in
                    BrowserChromeAppearance.windowCornerRadius(from: proxy.containerCornerInsets)
                } action: { radius in
                    windowCornerRadius = radius
                }
                // A full-screen window keeps reporting the corners it has as a
                // window, so whether it is full screen comes from AppKit.
                .background {
                    BrowserWindowFullScreenBridge(isFullScreen: $isWindowFullScreen).accessibilityHidden(true)
                }
            #endif
    }
}
