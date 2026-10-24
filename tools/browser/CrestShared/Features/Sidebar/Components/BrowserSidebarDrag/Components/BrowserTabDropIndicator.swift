import SwiftUI

struct BrowserTabDropIndicator: View {
    let location: BrowserTabDropLocation
    let dragState: BrowserTabDragState
    let isTargeted: Bool

    var body: some View {
        Capsule()
            .fill(CrestColor.dropIndicator)
            .frame(height: 2)
            .padding(.horizontal, CrestSpacing.large)
            .opacity(isVisible ? 1 : 0)
            .zIndex(3)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private var isVisible: Bool {
        _ = isTargeted
        return dragState.showsDropIndicator(at: location)
    }
}
