import SwiftUI

/// Hosts the native reorder destination for one region of the touch shell.
/// Both the sidebar and `MobileSplitContentDropFeed` use this adapter, so drop
/// positions, commits and immediate row activation follow the same path.
///
/// Attached to a whole region rather than to the runs inside it. On the sidebar
/// that is what reaches the pinned grid, which sits outside the scrolling list;
/// a feed attached to the list alone never sees the pointer over pinned, and a
/// tab could not be dropped there. The reorder state resolves everything from a
/// single global point regardless, so all this has to do is convert the drop's
/// local location using the region's own origin.
struct MobileBrowserReorderDropFeed: ViewModifier {
    @Environment(BrowserSidebarInteractionState.self) private var sidebarInteraction

    let browser: BrowserStore
    let spaceAccess: BrowserSpaceAccessController

    /// Where the fed region sits, so the delegate can report positions in the
    /// same global space the zones measured themselves in.
    @State private var origin = CGPoint.zero

    func body(content: Content) -> some View {
        content
            .contentShape(.rect)
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: BrowserSidebarReorderSpace.globalSpace)
            } action: { frame in
                origin = frame.origin
            }
            .overlay {
                BrowserMobileReorderDropTarget(
                    reorder: BrowserSidebarReorderContext(
                        browser: browser,
                        spaceAccess: spaceAccess,
                        state: sidebarInteraction.sidebarReorderState
                    ),
                    origin: origin
                )
                // A committed drop must not intercept the next tap.
                .allowsHitTesting(sidebarInteraction.sidebarReorderState.hasLiftInFlight)
                .accessibilityHidden(true)
            }
    }
}
