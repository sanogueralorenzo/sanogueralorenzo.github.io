import SwiftUI

/// Where a window's page and Space controls live: in Crest's own chrome, or in
/// the system toolbar where iOS lays bars out down the side of the window, as
/// on iPhone Duo. The controls move rather than repeat, so the chrome that
/// draws them asks the placement instead of asking which device it is on.
struct MobileBrowserControlPlacement: Equatable, Sendable {
    // MARK: - Static Variables

    static let chrome = MobileBrowserControlPlacement(
        name: "chrome",
        movesControlsToToolbar: false
    )

    static let sideToolbar = MobileBrowserControlPlacement(
        name: "sideToolbar",
        movesControlsToToolbar: true
    )

    // MARK: - Variables

    let name: String

    /// Whether the controls are toolbar items rather than drawn in the chrome.
    let movesControlsToToolbar: Bool

    /// The system bars' visibility: shown only to carry the moved controls.
    var barVisibility: Visibility {
        movesControlsToToolbar ? .automatic : .hidden
    }

    // MARK: - Initializers

    private init(name: String, movesControlsToToolbar: Bool) {
        self.name = name
        self.movesControlsToToolbar = movesControlsToToolbar
    }

    // MARK: - Actions - Sizing

    /// The placement for a window whose system bars prefer `verticalEdge`, or
    /// that lays them out across the top and bottom when there is none.
    static func fitting(verticalEdge: HorizontalEdge?) -> MobileBrowserControlPlacement {
        verticalEdge == nil ? .chrome : .sideToolbar
    }

    // MARK: - Actions - Layout

    /// The page frame's insets. Where the controls move to the side toolbar the
    /// display rounds its corners far more than a page frame does, so a page
    /// that reaches the window's leading edge stands off it, and off the top
    /// and bottom, by the layout margin, and its corners clear the display's.
    func pageInsets(_ insets: EdgeInsets) -> EdgeInsets {
        guard movesControlsToToolbar, insets.leading > 0 else { return insets }
        let margin = MobileBrowserRootLayout.displayEdgeMargin
        return EdgeInsets(
            top: max(insets.top, margin),
            leading: max(insets.leading, margin),
            bottom: max(insets.bottom, margin),
            trailing: insets.trailing
        )
    }

    // MARK: - Actions - Identity

    static func == (lhs: MobileBrowserControlPlacement, rhs: MobileBrowserControlPlacement) -> Bool {
        lhs.name == rhs.name
    }
}

extension EnvironmentValues {
    @Entry var mobileBrowserControlPlacement: MobileBrowserControlPlacement = .chrome
}
