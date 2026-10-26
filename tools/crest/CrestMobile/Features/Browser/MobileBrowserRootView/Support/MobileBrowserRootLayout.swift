import CoreGraphics

/// Feature-specific chrome geometry; cross-feature hit targets come from `CrestLayout`.
enum MobileBrowserChromeLayout {
    static let compactToolbarSpacing: CGFloat = 8
    static let compactToolbarHorizontalPadding: CGFloat = 10
    static let compactToolbarVerticalPadding: CGFloat = 6
    static let compactToolbarSymbolSize: CGFloat = 16

    /// How far a finger travels before it counts as interacting with a
    /// transient sidebar and holds the dismissal timer open.
    ///
    /// It may not be zero. The keep-alive rides a `simultaneousGesture` over the
    /// whole sidebar, rows included, and a zero-distance drag begins on
    /// touch-down — before `UIDragInteraction`'s long press has had a chance to
    /// settle into the lift a row's reorder depends on. The threshold is the
    /// same order as the slop UIKit already allows that press, so the keep-alive
    /// still catches a scroll and can no longer take the touch away from a lift
    /// that has not started yet.
    static let transientSidebarKeepAliveDistance: CGFloat = 10

    /// Where the find bar is placed. What it is made of now comes from the
    /// shared `BrowserFindBarMetrics` touch profile.
    static let regularFindMaximumWidth: CGFloat = 440
    static let compactFindHorizontalPadding: CGFloat = 10
    static let regularFindHorizontalPadding: CGFloat = 12
    static let regularFindTopPadding: CGFloat = 12
    static let compactFindToolbarGap: CGFloat = 14
    static let findFallbackBottomPadding: CGFloat = 12

    static let historyDividerHeight: CGFloat = 18
    static let historyDividerOpacity = 0.24
    static let historyCapsuleHorizontalPadding: CGFloat = 2
}

/// Geometry and timing owned by the mobile browser composition shell.
enum MobileBrowserRootLayout {
    static let defaultRegularSidebarWidth: CGFloat = 240
    static let resizeHandleOverlap: CGFloat = 8

    /// The system's layout margin, kept between chrome and a display edge
    /// with nothing else in between.
    static let displayEdgeMargin: CGFloat = 20

    /// How far chrome that starts in a corner of the display stands from its
    /// top edge, so a rounded corner as large as iPhone Duo's clears it.
    static let displayCornerClearance: CGFloat = 40

    static let compactOverlayTopPadding: CGFloat = 12
    static let regularOverlayTopPadding: CGFloat = 18

    static let feedbackHorizontalPadding: CGFloat = 14
    static let feedbackHeight: CGFloat = 40
    static let feedbackShadowRadius: CGFloat = 16
    static let feedbackShadowOffset: CGFloat = 8
    static let feedbackVisibilityDuration: Duration = .seconds(1.4)

    static let paletteLayer: Double = 10
    static let feedbackLayer: Double = 30
    static let utilityLayer: Double = 8

    /// Gives detached sidebar controls the same breathing room as the card's
    /// other floating chrome without moving their docked-window alignment.
    static let floatingSidebarBottomChromeInset: CGFloat = 6
}

enum MobileBrowserRootPreferences {
    /// Keep the existing key so current installs retain their preferred width.
    /// The value now applies to every expanded iOS layout, not only iPad.
    static let adaptiveSidebarWidthKey = "crest.sidebar.width.ipad"

    /// Whether a narrow window may float its sidebar over the page instead of
    /// keeping the full-screen tab viewer. Off unless the person allows it.
    static let allowsFloatingSidebarKey = "crest.sidebar.allows-floating"

    @MainActor
    static var allowsFloatingSidebar: Bool {
        BrowserChromeAppearancePreference.defaults.bool(forKey: allowsFloatingSidebarKey)
    }
}

enum MobileCompactDomainChipLayout {
    static let visibleHeight: CGFloat = 36
    static let minimumHitTarget = CrestLayout.minimumHitTarget
    static let horizontalPadding: CGFloat = 14
    static let outerHorizontalPadding: CGFloat = 12
}

enum MobileCompactTabViewerLayout {
    static let showsTopAddressBar = false
}
