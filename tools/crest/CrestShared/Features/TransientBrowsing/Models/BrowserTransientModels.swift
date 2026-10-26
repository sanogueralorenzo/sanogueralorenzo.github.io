import Foundation
import SwiftUI

/// The words one transient overlay uses for itself.
///
/// The surface is one thing; what it is called is not. A macOS window calls it
/// a Peek, an iPhone calls the same card a Quick Window when it was opened
/// from a lookup, and help text mentioning a keyboard shortcut only belongs
/// where there is a keyboard. So the strings arrive as input, written at the
/// shell that knows which name applies, rather than being chosen here.
struct BrowserTransientOverlayVocabulary {
    let closeAccessibilityLabel: LocalizedStringKey
    let closeHelp: LocalizedStringKey

    /// Shown while the page behind the card is still being built.
    let loadingTitle: LocalizedStringKey

    /// Shown once the page has been given up under memory pressure, with the
    /// button that brings it back.
    let releasedTitle: LocalizedStringKey
    let releasedDescription: LocalizedStringKey
    let restoreTitle: LocalizedStringKey
}

/// What a transient overlay's card has to draw where the web view goes.
///
/// The page itself is a platform type, so the shell answers the two facts the
/// shared card branches on and supplies the web view through its own slot.
struct BrowserTransientPageStatus {
    /// Whether the shell's web content slot has a page to draw.
    let hasPage: Bool

    /// Whether the page was given up under memory pressure and can be brought
    /// back, as opposed to never having arrived.
    let wasReleasedForMemoryPressure: Bool

    /// The accessibility label for the cover drawn over a page that has been
    /// handed a URL but has painted nothing, or `nil` on a shell that has no
    /// such cover. A shell that stages its overlay before committing has the
    /// card on screen empty already, and a second cover would only flash.
    var initialLoadingCoverLabel: LocalizedStringKey?
}

/// Everything a transient overlay's card can be asked to do.
///
/// The struct is main-actor isolated because a view holds it; the closures are
/// plain non-`Sendable` values called during that view's own updates.
@MainActor
struct BrowserTransientCardActions {
    let dismiss: () -> Void
    let promote: (BrowserSpaceRuntimeAssignment) -> Void

    /// Rebuilds a page released under memory pressure.
    let restore: () -> Void
}

struct BrowserTransientPageSnapshot: Equatable, Sendable {
    let assignment: BrowserSpaceRuntimeAssignment
    let url: URL
    let title: String?
    /// The core page that last showed it, which may be gone.
    let pageID: UUID
}
