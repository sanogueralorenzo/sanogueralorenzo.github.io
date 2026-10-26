import CoreGraphics
import SwiftUI

/// Where each presented card sits, so a window-level mouse-down can say which
/// card it landed in.
///
/// A local `NSEvent` monitor is the only thing that can see a click web content
/// consumes, and it gets a point rather than a view. Frames are how that point
/// becomes a card. They are registered in a named coordinate space owned by the
/// split surface — not `.global` — because the monitor's `NSView` spans exactly
/// the view that declares that space, which makes the AppKit conversion of the
/// event location an identity rather than an assumption about where a window's
/// content view begins relative to its titlebar.
///
/// Deliberately not `@Observable`. Nothing renders from these frames; they are
/// written *during* layout and read only when a click arrives. Observation would
/// invalidate the view that just produced the frame it recorded.
///
/// Not on `BrowserStore` either: which cards are where is presentation state
/// belonging to one window's content area, and a second window presenting the
/// same group would fight over the same keys.
///
/// Work package 8 registers card frames again, in global coordinates, inside
/// `BrowserSidebarReorderState` — drag-drop resolution compares one pointer
/// against sidebar zones and cards together, which needs the shared global
/// space. The two registries coexist by design: same subject, different
/// coordinate space, different owner and lifetime.
@MainActor
final class BrowserSplitCardFrameRegistry {
    /// The coordinate space cards register in and the click monitor reads.
    nonisolated static let coordinateSpaceName = "crest.split-view.card-frames"

    nonisolated static var coordinateSpace: NamedCoordinateSpace {
        .named(coordinateSpaceName)
    }

    private var framesByTabID: [UUID: CGRect] = [:]

    func register(_ frame: CGRect, for tabID: UUID) {
        framesByTabID[tabID] = frame
    }

    func removeFrame(for tabID: UUID) {
        framesByTabID[tabID] = nil
    }

    func frame(for tabID: UUID) -> CGRect? {
        framesByTabID[tabID]
    }

    /// Every measured card, by tab. A carry compares the pointer against the
    /// cards it is *not* holding, so it needs to know which frame is whose.
    ///
    /// Deliberately unfiltered, and deliberately not ordered here. The registry
    /// records what it was told and outlives the cards it was told about: a
    /// member the row is animating out keeps its frame until SwiftUI runs its
    /// disappearance, and until then this holds a rectangle that overlaps the
    /// cards which closed up around it. Only the row knows which tabs are still
    /// members, so every geometric question the carry asks is asked of the
    /// members — see `BrowserSplitCardLift.card(at:members:cardFrames:)`
    /// and `orderedMemberFrames(members:cardFrames:)`.
    var frames: [UUID: CGRect] {
        framesByTabID
    }

    /// The card `point` falls inside. Cards never overlap, so the first hit is
    /// the only hit.
    func tabID(containing point: CGPoint) -> UUID? {
        framesByTabID.first { $0.value.contains(point) }?.key
    }
}
