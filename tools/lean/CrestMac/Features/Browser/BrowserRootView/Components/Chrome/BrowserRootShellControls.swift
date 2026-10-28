import SwiftUI

/// The edge observes the pointer without intercepting page input.
struct BrowserRootShellControls: View {
    let model: BrowserRootModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if !model.isSidebarPresented {
            Color.clear
                .frame(width: BrowserSidebarPresentation.floatingHoverMargin)
                .frame(maxHeight: .infinity)
                .overlay {
                    BrowserCollapsedSidebarHoverTracker { isHovering in
                        guard isHovering, model.isWindowFocused else { return }
                        model.revealSidebarFromPointer(reduceMotion: reduceMotion)
                    }
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}
