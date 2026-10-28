import SwiftUI

/// One side of the frame, handing a swipe in from it to the page's own swipe.
struct MobileHistorySwipeBorderSide: View {
    let page: MobileBrowserPage
    let direction: MobileHistorySwipeDirection

    /// Whether the page is following this swipe, or it was not one.
    @State private var isTracking = false
    @State private var isDeclined = false
    @GestureState private var isTouching = false

    var body: some View {
        Color.clear
            .contentShape(.rect)
            .gesture(
                DragGesture(minimumDistance: CrestSpacing.small, coordinateSpace: .global)
                    .updating($isTouching) { _, isTouching, _ in isTouching = true }
                    .onChanged(changed)
                    .onEnded(ended)
            )
            .onChange(of: isTouching) { _, isTouching in
                // A swipe the system takes away ends here without `ended`.
                guard !isTouching else { return }
                if isTracking {
                    page.historySwipe?.endBesidePage(translation: .zero, velocity: .zero)
                }
                isTracking = false
                isDeclined = false
            }
            .accessibilityHidden(true)
    }

    private func changed(_ value: DragGesture.Value) {
        guard !isTracking else {
            page.historySwipe?.moveBesidePage(translation: point(value.translation))
            return
        }
        guard !isDeclined else { return }
        // Only a mostly sideways move counts; anything else is left alone.
        guard abs(value.translation.width) > abs(value.translation.height),
            page.historySwipe?.beginBesidePage(from: direction, at: value.startLocation) == true
        else {
            isDeclined = true
            return
        }
        isTracking = true
        page.historySwipe?.moveBesidePage(translation: point(value.translation))
    }

    private func ended(_ value: DragGesture.Value) {
        if isTracking {
            page.historySwipe?.endBesidePage(
                translation: point(value.translation),
                velocity: point(value.velocity)
            )
        }
        isTracking = false
        isDeclined = false
    }

    private func point(_ size: CGSize) -> CGPoint {
        CGPoint(x: size.width, y: size.height)
    }
}
