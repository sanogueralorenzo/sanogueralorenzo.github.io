import SwiftUI

/// Feeds the reorder state the pointer samples a touch lift reports while the
/// finger is over the content area, so a tab carried out of the sidebar can be
/// dropped onto the cards on show.
///
/// macOS needs nothing here: its lift is a `DragGesture` that streams positions
/// in the window's own global space for as long as the button is down, wherever
/// the pointer travels. A touch lift is a system drag session, and a session
/// reports positions only to the drop interactions it passes over — so the page
/// area has to offer one or the finger goes dark the moment it leaves the
/// sidebar.
///
/// The feed rides on a capture layer above the page rather than on the page
/// surface itself, for one reason: a live `WKWebView` installs a drop
/// interaction of its own, and it is the innermost one under the finger. A page
/// that answers a drop — an editable field, a script listening for `dragover` —
/// would take the release, and the drop that lands a card would never reach us.
/// A layer drawn over the page is nearer the finger than anything the page can
/// install, so what the page does with the session stops mattering.
///
/// The layer only hit-tests while a lift is in flight, which costs the page
/// nothing: a system drag already owns the touch that is carrying it, so there
/// is no interaction being taken away. `hasLiftInFlight` rather than
/// `isDragging`, because a lift is staged by the native source and promoted
/// by the first position a delegate reports — and this feed may be the first
/// delegate to report one, which it cannot do if the layer waits for the
/// promotion it is supposed to cause.
struct MobileSplitContentDropFeed: ViewModifier {
    @Environment(BrowserSidebarInteractionState.self) private var sidebarInteraction

    let browser: BrowserStore
    let spaceAccess: BrowserSpaceAccessController

    func body(content: Content) -> some View {
        content.overlay {
            Color.clear
                .contentShape(.rect)
                .modifier(
                    MobileBrowserReorderDropFeed(
                        browser: browser,
                        spaceAccess: spaceAccess
                    )
                )
                .allowsHitTesting(
                    sidebarInteraction.sidebarReorderState.hasLiftInFlight
                )
                .accessibilityHidden(true)
        }
    }
}
