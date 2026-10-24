import SwiftUI

/// Registers a sidebar drop zone, clipped to its visible scroll and pager regions.
struct BrowserSidebarReorderZoneModifier: ViewModifier {
    let target: BrowserSidebarReorderZone.Target
    let state: BrowserSidebarReorderState
    /// An inactive zone unregisters itself, so a folder can offer "drop inside"
    /// only while it is collapsed without changing the view's identity.
    var isActive = true
    /// Row-local targets follow the input role without invalidating row content.
    var requiresSelectedSpace = false
    /// Trimmed from the top of the zone. A folder group's nested-folder section
    /// must not claim the group's own header row, or the header stops being a
    /// place to drop *beside* the folder.
    var topInset: CGFloat = 0
    var minimumHeight: CGFloat = 0

    /// Identity for this registration. The mobile space pager keeps neighbouring
    /// pages alive and they register the same targets, so registrations must not
    /// key on the target or offscreen pages clobber the visible one.
    @State private var identity = UUID()
    @Environment(\.browserInteractionCapabilities) private var capabilities
    @Environment(\.browserSidebarScrollRegionID) private var scrollRegionID
    @Environment(\.browserSidebarDropViewportID) private var sidebarViewportID
    @Environment(\.sidebarSpaceIsSelected) private var isSelected

    func body(content: Content) -> some View {
        let isActive =
            self.isActive
            && (!requiresSelectedSpace
                || SidebarSpaceRole.permitsInteraction(isSelected: isSelected, isAvailable: true))
        let target = target
        let topInset = topInset
        let minimumHeight = minimumHeight
        let supportsTouch = capabilities.supportsTouch
        return
            content
            .onGeometryChange(for: BrowserSidebarReorderZone?.self) { proxy in
                guard isActive else { return nil }
                return BrowserSidebarReorderZone(
                    target: target,
                    frame: Self.resolvedFrame(
                        proxy.frame(in: BrowserSidebarReorderSpace.globalSpace), target: target, topInset: topInset),
                    minimumHeight: minimumHeight,
                    supportsTouch: supportsTouch)
            } action: { zone in
                guard let zone else {
                    state.removeZone(for: identity)
                    return
                }
                state.register(
                    zone: zone,
                    for: identity,
                    sidebarViewportID: sidebarViewportID,
                    scrollRegionID: scrollRegionID
                )
            }
            .onDisappear {
                state.removeZone(for: identity)
            }
    }

    /// A nesting target claims only the middle of its row so the edges stay
    /// available for reordering past it.
    nonisolated private static func resolvedFrame(
        _ frame: CGRect, target: BrowserSidebarReorderZone.Target, topInset: CGFloat
    ) -> CGRect {
        if target.nests { return BrowserSidebarReorderZone.nestingFrame(for: frame) }
        guard topInset > 0, frame.height > topInset else { return frame }
        return CGRect(
            x: frame.minX,
            y: frame.minY + topInset,
            width: frame.width,
            height: frame.height - topInset
        )
    }
}

extension View {
    func browserSidebarReorderZone(
        _ target: BrowserSidebarReorderZone.Target,
        state: BrowserSidebarReorderState,
        isActive: Bool = true,
        requiresSelectedSpace: Bool = false,
        topInset: CGFloat = 0,
        minimumHeight: CGFloat = 0
    ) -> some View {
        modifier(
            BrowserSidebarReorderZoneModifier(
                target: target,
                state: state,
                isActive: isActive,
                requiresSelectedSpace: requiresSelectedSpace,
                topInset: topInset, minimumHeight: minimumHeight
            )
        )
    }
}
