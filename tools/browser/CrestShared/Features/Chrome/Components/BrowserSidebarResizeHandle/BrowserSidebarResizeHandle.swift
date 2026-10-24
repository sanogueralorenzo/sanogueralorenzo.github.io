import SwiftUI

struct BrowserSidebarResizeHandle: View {
    @Binding var width: CGFloat
    var onResizeEnded: (CGFloat) -> Void = { _ in }
    var edge: HorizontalEdge = .leading

    @Environment(\.layoutDirection) private var layoutDirection
    @State private var dragStartWidth: CGFloat?
    @State private var isActive = false

    var body: some View {
        Color.clear
            .frame(width: BrowserSidebarResizeHandleMetrics.hitWidth)
            .contentShape(.rect)
            .modifier(BrowserPlatformColumnResizePointerModifier())
            .overlay {
                Capsule()
                    .fill(
                        .primary.opacity(
                            isActive
                                ? BrowserSidebarResizeHandleMetrics.activeIndicatorOpacity
                                : 0
                        )
                    )
                    .frame(
                        width: BrowserSidebarResizeHandleMetrics.indicatorWidth,
                        height: BrowserSidebarResizeHandleMetrics.indicatorHeight
                    )
                    .accessibilityHidden(true)
            }
            .gesture(
                // The handle moves as width changes; measure in stationary coordinates.
                DragGesture(minimumDistance: 0, coordinateSpace: .global)
                    .onChanged(resize)
                    .onEnded(endResize)
            )
            .accessibilityLabel("Resize Sidebar")
            .accessibilityValue("\(Int(width.rounded())) points")
            .accessibilityAdjustableAction(adjustWidth)
    }

    private func resize(_ value: DragGesture.Value) {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            let start = dragStartWidth ?? width
            dragStartWidth = start
            isActive = true
            width = BrowserChromeLayout.clampedSidebarWidth(
                start
                    + layoutDirection.sidebarResizeDelta(value.translation.width) * (edge == .leading ? 1 : -1)
            )
        }
    }

    private func endResize(_ value: DragGesture.Value) {
        resize(value)
        dragStartWidth = nil
        isActive = false
        onResizeEnded(width)
    }

    private func adjustWidth(_ direction: AccessibilityAdjustmentDirection) {
        let delta: CGFloat
        switch direction {
        case .increment:
            delta = BrowserSidebarResizeHandleMetrics.accessibilityStep
        case .decrement:
            delta = -BrowserSidebarResizeHandleMetrics.accessibilityStep
        @unknown default:
            delta = 0
        }
        guard delta != 0 else { return }
        width = BrowserChromeLayout.clampedSidebarWidth(width + delta)
        onResizeEnded(width)
    }
}
