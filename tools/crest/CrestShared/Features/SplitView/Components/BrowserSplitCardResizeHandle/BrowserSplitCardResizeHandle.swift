import SwiftUI

/// The affordance that moves one boundary between two split cards.
///
/// It lives in the gap between the cards and overhangs each of them slightly,
/// so the pointer target is comfortable without the control ever covering
/// content. The drag reports its total travel rather than each frame's step —
/// which is what `BrowserSplitWidthTransaction.resize(dividerIndex:delta:containerWidth:)`
/// expects — and the durable per-window record advances once, on release.
///
/// That travel is measured in `BrowserSplitResizeSpace`, the columns row, and
/// never in the handle's own space. The row positions this handle from the
/// fractions the drag writes, so the handle's frame moves with the boundary and
/// a translation measured against it reports the pointer's travel minus its own
/// — a feedback loop that halves tracking and turns a point of pointer noise
/// into a standing oscillation.
///
/// The capsule remains visible at rest and shares the existing resize target
/// and gesture on every platform.
/// `BrowserPlatformColumnResizePointerModifier` gives each platform its own
/// answer to "this boundary moves" rather than leaving it to be discovered.
struct BrowserSplitCardResizeHandle: View {
    /// The gap this handle sits in: the one after the card at this index.
    let dividerIndex: Int
    /// The drag's travel since it began, measured toward the trailing edge in
    /// the reading direction.
    let resize: (CGFloat) -> Void
    let commit: () -> Void
    var accessibilityTitle: LocalizedStringKey = "Resize Split View Columns"
    var accessibilityMeasurement: String?
    var accessibilityDirection: CGFloat = 1

    @Environment(\.layoutDirection) private var layoutDirection
    @State private var isDragging = false

    var body: some View {
        Color.clear
            .frame(width: BrowserSplitLayoutMetrics.resizeHandleHitWidth)
            .contentShape(.rect)
            .modifier(BrowserPlatformColumnResizePointerModifier())
            .overlay {
                Capsule()
                    .fill(
                        .primary.opacity(
                            isDragging
                                ? BrowserSplitCardResizeHandleMetrics.activeIndicatorOpacity
                                : idleIndicatorOpacity
                        )
                    )
                    .frame(
                        width: BrowserSplitCardResizeHandleMetrics.indicatorWidth,
                        height: BrowserSplitCardResizeHandleMetrics.indicatorHeight
                    )
                    .accessibilityHidden(true)
            }
            .gesture(
                DragGesture(
                    minimumDistance: 0,
                    coordinateSpace: BrowserSplitResizeSpace.coordinateSpace
                )
                .onChanged(dragChanged)
                .onEnded(dragEnded)
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityTitle)
            .accessibilityValue(accessibilityMeasurement ?? String(localized: "Divider \(dividerIndex + 1)"))
            .accessibilityAdjustableAction(adjustWidth)
    }

    private var idleIndicatorOpacity: Double {
        0.18
    }

    private func dragChanged(_ value: DragGesture.Value) {
        isDragging = true
        resize(semanticTranslation(value.translation.width))
    }

    private func dragEnded(_ value: DragGesture.Value) {
        isDragging = false
        resize(semanticTranslation(value.translation.width))
        commit()
    }

    /// Each accessibility step is its own complete interaction: it resizes and
    /// commits, so the next step measures from the layout now on screen.
    private func adjustWidth(_ direction: AccessibilityAdjustmentDirection) {
        let step = BrowserSplitCardResizeHandleMetrics.accessibilityStep
        let delta: CGFloat
        switch direction {
        case .increment:
            delta = step
        case .decrement:
            delta = -step
        @unknown default:
            delta = 0
        }
        guard delta != 0 else { return }
        resize(delta * accessibilityDirection)
        commit()
    }

    private func semanticTranslation(_ translation: CGFloat) -> CGFloat {
        layoutDirection.semanticHorizontalTranslation(translation)
    }
}
