import AppKit
import CoreGraphics

/// Everything the split surface's pointer monitor can do to a carry, and the one
/// thing it may ask about one.
///
/// Closures rather than a delegate, and a value rather than an object, because
/// the split between the two sides is total: the monitor owns the event stream
/// and nothing else, and every decision — which card a point is in, whether the
/// row can spare one, what the session should be told on release — belongs to
/// the view that already holds the frames, the members, and the store.
///
/// `begin` answers whether a card was picked up, which is also the monitor's
/// answer to whether it should keep the event. A refused pickup is an ordinary
/// click and continues to the page untouched.
///
/// `isCarrying` is asked rather than remembered, and that is the important one.
/// A monitor that kept its own copy of "a card is on the pointer" would be
/// keeping a second answer to a question the lift state already answers — and a
/// second answer can be left behind. Every way a carry can end without passing
/// through the monitor (the card leaving the row, the window going away, the
/// state being abandoned outright) would strand that copy at `true`, and a
/// monitor that believes it is carrying swallows every press that follows.
struct BrowserSplitCardLiftGesture {
    let begin: @MainActor @Sendable (CGPoint, BrowserKeyboardModifierFlags) -> Bool
    let update: @MainActor @Sendable (CGPoint) -> Void
    let drop: @MainActor @Sendable () -> Void
    let cancel: @MainActor @Sendable () -> Void
    /// Whether a card is on the pointer at this instant, straight from the state
    /// that owns the carry.
    let isCarrying: @MainActor @Sendable () -> Bool
}

/// Everything the floating preview window needs to draw a carried Split View
/// card, as one comparable value.
///
/// Resolved where the Space is already in hand, the way the sidebar's own lift
/// subject is: the carry holds a `UUID` and a picture, and the preview shows a
/// real tab's title and favicon while the picture is still on its way. One value
/// rather than a handful of properties so the window host can tell a frame that
/// changed something from a frame that changed nothing.
struct BrowserSplitCardLiftPreviewContent: Equatable {
    /// The carried tab's icon and title, drawn until the picture arrives.
    let favicon: BrowserTabFaviconSubject
    let title: String
    /// The Space profile the fallback art resolves the favicon against.
    let profileID: UUID
    /// The page as it was rendered at pickup, once WebKit has handed it over.
    let snapshot: NSImage?
    /// Top-left of the card in the source browser window's global space.
    let origin: CGPoint
    let size: CGSize
    /// The corner the card had in the row, so it lifts out with the same shape.
    let cornerRadius: CGFloat
    /// Where inside the card the pointer took hold. The rise is scaled about
    /// this point, so the pixel somebody grabbed stays under the cursor.
    let grabFraction: CGPoint
    /// True while the preview is fading onto the slot the card has already
    /// returned to.
    let isSettling: Bool
    /// Passed in rather than read from the environment: the preview is hosted in
    /// a window of its own, which inherits nothing from the browser's.
    let reduceMotion: Bool
}

/// One carry, told apart from every other carry the window has ever had.
///
/// A pickup asks WebKit for a picture before it changes anything on screen, so
/// the request is in flight before there is a carry for it to belong to. The
/// token is what the request holds on to in the meantime: the state hands one out
/// when a pickup is staged, the carry keeps it, and an arriving image is matched
/// against the carry's own token rather than against the tab it pictures.
///
/// A tab is not enough on its own. Picking the same card up twice in quick
/// succession produces two requests for one `UUID`, and the first answer must
/// not be crossfaded into the second carry — it is a picture of a row that has
/// already moved on. Identity per carry says so; identity per tab cannot.
struct BrowserSplitCardLiftToken: Hashable, Sendable {
    /// Monotonic within one window. Never reused, so a stale answer can only
    /// ever fail to match.
    let sequence: UInt64
}
