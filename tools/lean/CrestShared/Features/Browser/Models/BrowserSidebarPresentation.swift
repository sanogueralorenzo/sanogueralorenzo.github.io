import SwiftUI

/// Where a window's sidebar is: beside the page, floating over it, or put away.
struct BrowserSidebarPresentation: Hashable, Sendable {
    // MARK: - Types

    /// Each place shows its own controls, so the view that builds them
    /// switches over the kind.
    enum Kinds: Sendable {
        case docked
        case floating
        case collapsed
    }

    // MARK: - Static Variables

    static let floatingCardInset: CGFloat = 6
    static let floatingHoverMargin: CGFloat = 32

    static let docked = BrowserSidebarPresentation(
        kind: .docked, name: "docked", showsSidebar: true, showsWindowControls: true, reservesSidebarWidth: true,
        toggles: { $0.toggleDockedSidebar() })
    static let floating = BrowserSidebarPresentation(
        kind: .floating, name: "floating", showsSidebar: true, showsWindowControls: true, reservesSidebarWidth: false,
        toggles: { $0.toggleFloatingSidebar() })
    static let collapsed = BrowserSidebarPresentation(
        kind: .collapsed, name: "collapsed", showsSidebar: false, showsWindowControls: false,
        reservesSidebarWidth: false, toggles: { $0.toggleCollapsedSidebar() })

    // MARK: - Variables

    let kind: Kinds
    let name: String
    let showsSidebar: Bool
    let showsWindowControls: Bool
    let reservesSidebarWidth: Bool

    /// Calls the handler's toggle for this place.
    private let toggles: @MainActor @Sendable (any BrowserSidebarToggleHandler) -> Void

    // MARK: - Initializers

    private init(
        kind: Kinds, name: String, showsSidebar: Bool, showsWindowControls: Bool, reservesSidebarWidth: Bool,
        toggles: @escaping @MainActor @Sendable (any BrowserSidebarToggleHandler) -> Void
    ) {
        self.kind = kind
        self.name = name
        self.showsSidebar = showsSidebar
        self.showsWindowControls = showsWindowControls
        self.reservesSidebarWidth = reservesSidebarWidth
        self.toggles = toggles
    }

    // MARK: - Actions - Layout

    static func floatingRegionWidth(sidebarWidth: CGFloat) -> CGFloat {
        sidebarWidth + (floatingCardInset * 2)
    }

    func reservedWidth(
        for sidebarWidth: CGFloat
    ) -> CGFloat {
        reservesSidebarWidth ? sidebarWidth : 0
    }

    // MARK: - Actions - Toggle

    /// Toggles the sidebar from here, as `handler` toggles a sidebar in this place.
    @MainActor
    func toggle(on handler: some BrowserSidebarToggleHandler) {
        toggles(handler)
    }

    // MARK: - Actions - Identity

    static func == (lhs: BrowserSidebarPresentation, rhs: BrowserSidebarPresentation) -> Bool {
        lhs.name == rhs.name
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }
}
