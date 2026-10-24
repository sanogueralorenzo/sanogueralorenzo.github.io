import SwiftUI

/// Pointer drags coexist with row buttons; the browser window draws their previews.
struct BrowserPlatformSidebarReorderLiftGesture: ViewModifier {
    /// A drag must travel this far before it lifts, so a sloppy click still
    /// selects a tab instead of starting a reorder.
    private static let liftDistance: CGFloat = 4

    var isEnabled = true
    /// Takes the pointer moving a lift, from where it began to where it is.
    let moved: (_ startLocation: CGPoint, _ location: CGPoint) -> Void
    /// Takes the pointer letting go.
    let released: () -> Void

    func body(content: Content) -> some View {
        content.simultaneousGesture(pointerDrag, including: isEnabled ? .all : .subviews)
    }

    private var pointerDrag: some Gesture {
        DragGesture(
            minimumDistance: Self.liftDistance,
            coordinateSpace: BrowserSidebarReorderSpace.coordinateSpace
        )
        .onChanged { value in
            moved(value.startLocation, value.location)
        }
        .onEnded { _ in released() }
    }
}
