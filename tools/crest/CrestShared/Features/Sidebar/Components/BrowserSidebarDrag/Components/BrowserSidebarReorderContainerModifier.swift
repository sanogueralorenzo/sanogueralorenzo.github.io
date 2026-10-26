import SwiftUI

/// Measures and moves a whole reorder item independently of its drag handle.
/// A folder registers this on its full section and arms the lift on its header.
struct BrowserSidebarReorderContainerModifier: ViewModifier {
    let item: BrowserSidebarReorderItem
    let section: BrowserSidebarReorderSection
    let reorder: BrowserSidebarReorderContext
    var parentItemID: BrowserSidebarReorderItemID?
    var isEnabled = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.browserSidebarScrollRegionID) private var scrollRegionID
    @Environment(\.browserSidebarWindowDrop) private var windowDrop

    /// Identity for this row's registration. A row that changes section keeps
    /// its item identity but is a different view on either side of the move, and
    /// the departing one leaves after the arriving one has measured itself —
    /// so removal has to name which view is leaving. See
    /// `BrowserSidebarReorderState.RegisteredRow`.
    @State private var identity = UUID()

    private var state: BrowserSidebarReorderState { reorder.state }

    private var isLifted: Bool {
        isEnabled && state.isLifted(item.id)
    }

    private var displacement: CGSize {
        !isEnabled || state.layout.isActive || section.usesGridOrdering ? .zero : state.displacement(for: item.id)
    }

    private var indicator: BrowserSidebarReorderIndicator? {
        !isEnabled || state.layout.isActive || section.usesGridOrdering ? nil : state.indicator(for: item.id)
    }

    private var topSpace: CGFloat { isEnabled ? state.layout.topSpace(for: item.id) : 0 }
    private var bottomSpace: CGFloat { isEnabled ? state.layout.bottomSpace(for: item.id) : 0 }
    private var hidesSource: Bool { isEnabled && state.hidesSource(item.id) }
    private var isRevealing: Bool { isEnabled && state.isRevealing(item.id) }

    func body(content: Content) -> some View {
        VStack(spacing: 0) {
            BrowserSidebarReorderGap(height: topSpace)
            content
                // Keep the gesture's content alive at its lifted dimensions while
                // its layout slot closes. Removing the view would cancel the drag.
                .frame(
                    height: isLifted && state.layout.isActive && !section.usesGridOrdering
                        ? state.frame(ofRow: item.id)?.height : nil,
                    alignment: .top
                )
                .onGeometryChange(for: BrowserSidebarReorderRow?.self) { proxy in
                    // Availability participates in the measured value so an
                    // unchanged frame is registered again when its Space returns.
                    guard isEnabled else { return nil }
                    return BrowserSidebarReorderRow(
                        id: item.id, space: item.spaceAssignment, section: section,
                        frame: proxy.frame(in: BrowserSidebarReorderSpace.globalSpace), parentItemID: parentItemID)
                } action: { row in
                    guard let row else {
                        state.removeRow(item.id, owner: identity)
                        return
                    }
                    // While lifted, this row's reported frame follows the pointer.
                    // Registering it would re-sort the section under the drag and
                    // corrupt the slot indices, so keep the frame it lifted from.
                    guard !isLifted else { return }
                    state.register(
                        row: row,
                        owner: identity,
                        scrollRegionID: scrollRegionID
                    )
                    windowDrop?.didMeasureRow(row)
                }
                .onDisappear {
                    state.removeRow(item.id, owner: identity)
                }
                .offset(x: displacement.width, y: displacement.height)
                .opacity(hidesSource && !isRevealing ? 0 : 1)
                .animation(nil, value: hidesSource)
                .animation(
                    Animation.easeOut(duration: 0.10).unlessReducingMotion(reduceMotion),
                    value: isRevealing
                )
                .frame(
                    height: isLifted && state.layout.isActive && !section.usesGridOrdering ? 0 : nil, alignment: .top
                )
                .overlay(alignment: indicatorAlignment) {
                    if let indicator {
                        BrowserSidebarReorderIndicatorLine(indicator: indicator)
                    }
                }
            BrowserSidebarReorderGap(height: bottomSpace)
        }
        // Layout capacity moves with the gap, across section boundaries.
        .animation(
            CrestMotion.dragSource.unlessReducingMotion(reduceMotion),
            value: [
                topSpace, bottomSpace,
                isLifted ? state.layout.height : 0,
            ]
        )
        .animation(
            CrestMotion.dragSource.unlessReducingMotion(reduceMotion),
            value: displacement
        )
    }

    private var indicatorAlignment: Alignment {
        guard let indicator else { return .top }
        switch (indicator.flowsHorizontally, indicator.side) {
        case (true, .before): return .leading
        case (true, .after): return .trailing
        case (false, .before): return .top
        case (false, .after): return .bottom
        }
    }

}

extension View {
    func browserSidebarReorderContainer(
        item: BrowserSidebarReorderItem,
        section: BrowserSidebarReorderSection,
        reorder: BrowserSidebarReorderContext,
        parentItemID: BrowserSidebarReorderItemID? = nil,
        isEnabled: Bool = true
    ) -> some View {
        modifier(
            BrowserSidebarReorderContainerModifier(
                item: item, section: section, reorder: reorder, parentItemID: parentItemID, isEnabled: isEnabled))
    }
}
