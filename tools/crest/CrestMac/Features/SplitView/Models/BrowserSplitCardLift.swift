import AppKit
import CoreGraphics

/// One Split View card, off the row and on the pointer.
///
/// Everything a carry needs, as one value: what was picked up, where it was
/// picked up from, where the pointer has taken it, and which slot it would drop
/// into if it were let go now. The row reads the gap out of it, the floating
/// preview window reads the pose out of it, and the release reads the move out
/// of it — three presentations of one carry rather than three copies of it.
struct BrowserSplitCardLift: Equatable {
    /// This carry's own identity, minted when the pickup was staged. An image
    /// asked for by an earlier carry cannot match it, so nothing this carry did
    /// not request can ever be shown on it.
    let token: BrowserSplitCardLiftToken
    let tabID: UUID
    /// The slot the card came from, so a cancelled carry has somewhere to be put
    /// back.
    let originIndex: Int
    /// The card's size at pickup. The preview keeps it for the whole carry: it
    /// is the card somebody picked up, not a card resized to whichever column
    /// the gap is currently standing in.
    let cardSize: CGSize
    /// Where inside the card the pointer took hold, as a fraction on each axis.
    let grabFraction: CGPoint
    /// The split surface's origin in the window-global space the preview window
    /// is pinned to.
    ///
    /// The pointer is reported in the surface's own card-frame space — the only
    /// space the card frames it is compared against exist in — and the preview
    /// is drawn in the window's, so one of the two has to carry the offset
    /// between them.
    ///
    /// Resampled with every pointer sample rather than taken once. Key events
    /// still reach the app during a carry, and the surface moves when the
    /// sidebar is toggled or the window enters full screen; an offset captured
    /// at pickup would leave the card hanging a sidebar's width from the cursor
    /// for the rest of the gesture.
    var surfaceOrigin: CGPoint
    /// The pointer, in the split surface's card-frame space.
    var pointer: CGPoint
    /// The slot the gap is standing in, and the member index a release commits.
    var gapIndex: Int
    /// The page as WebKit had it rendered at pickup.
    ///
    /// `nil` until it arrives, which is a frame or two after the card is already
    /// moving: the carry never waits for the image.
    var snapshot: NSImage?
    /// True from the release until the preview has finished settling, during
    /// which the card is back in the row and the preview is only fading off it.
    var isSettling = false

    /// Top-left of the preview, in the window-global space the preview window is
    /// pinned to.
    ///
    /// Pure arithmetic on the pointer, exactly like the sidebar's own anchored
    /// origin: the grabbed fraction of the card, subtracted from where the
    /// pointer is now. Nothing here consults a frame the row is animating.
    var previewOrigin: CGPoint {
        CGPoint(
            x: surfaceOrigin.x + pointer.x - grabFraction.x * cardSize.width,
            y: surfaceOrigin.y + pointer.y - grabFraction.y * cardSize.height
        )
    }
}
