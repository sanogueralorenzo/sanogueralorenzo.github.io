import SwiftUI

/// What this shell calls the shared transient overlay.
///
/// On macOS the surface is always a Peek — a Quick Window is its own window
/// scene here, not a card — and there is always a keyboard to mention. The
/// strings stay in this target so the shared components never have to guess
/// which name applies.
enum BrowserPeekVocabulary {
    static var overlay: BrowserTransientOverlayVocabulary {
        BrowserTransientOverlayVocabulary(
            closeAccessibilityLabel: "Close Peek",
            closeHelp: "Close Peek (Esc or ⌘W)",
            loadingTitle: "Opening Peek…",
            releasedTitle: "Peek Released",
            releasedDescription:
                "Crest released this temporary page to reduce memory use.",
            restoreTitle: "Reload Peek"
        )
    }

    static var initialLoadingCoverLabel: LocalizedStringKey {
        "Loading Peek"
    }

    /// A Peek sits inside a window the person is still looking at, so a Space
    /// disappearing under it is explained rather than silently closed.
    static var unavailableSpace: BrowserTransientUnavailableSpacePresentation {
        .explanation(
            BrowserTransientUnavailableSpaceVocabulary(
                title: "Peek Unavailable",
                systemImage: "eye.slash",
                description:
                    "The Space that opened this Peek is no longer available.",
                dismissTitle: "Close Peek"
            )
        )
    }
}
