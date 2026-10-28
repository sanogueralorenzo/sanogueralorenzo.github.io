import SwiftUI

/// The address bar's swipe through the shown Space's tabs.
///
/// A drag that is first of all horizontal moves the page with it, and its
/// release lands on the neighbour or springs back. Any other drag is left to
/// the bar's other gestures, such as the upward reveal of the tab viewer, and
/// an address being edited is never swiped.
struct MobileTabSwipeGesture: ViewModifier {
    let swipe: MobileTabSwipe
    let isEnabled: Bool
    let neighbors: () -> SwipeNeighborTabs
    let land: (UUID) -> Void

    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @GestureState private var isDragging = false

    func body(content: Content) -> some View {
        content
            .simultaneousGesture(drag, including: isEnabled ? .all : .subviews)
            .onChange(of: isDragging) { _, dragging in
                // A drag the system cancelled never ends; put the page back.
                if !dragging { release(.zero) }
            }
            .sensoryFeedback(.impact(weight: .light), trigger: swipe.boundaryHits)
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: MobileTabSwipe.recognitionDistance, coordinateSpace: .local)
            .updating($isDragging) { _, dragging, _ in dragging = true }
            .onChanged { value in
                swipe.track(
                    value.translation, layoutDirection: layoutDirection, reduceMotion: reduceMotion,
                    neighbors: neighbors)
            }
            .onEnded { value in release(value.predictedEndTranslation) }
    }

    private func release(_ predictedTranslation: CGSize) {
        swipe.release(predictedTranslation, layoutDirection: layoutDirection, reduceMotion: reduceMotion, land: land)
    }
}
