import SwiftUI

/// Independent interaction features supplied by the shell. Touch and hover may coexist.
struct BrowserInteractionCapabilities: Equatable, Sendable {
    /// Enables affordances revealed by a resting pointer.
    var supportsHover = true

    /// Keeps touch-sized targets available, including when a pointer is attached.
    var supportsTouch = false

    /// Reserves drop targets at section boundaries for imprecise input, with a
    /// landing band at the end of each run.
    var reservesReorderSectionZones = false

    /// Uses the system navigation transition when a row pushes a page.
    var usesNativeNavigationTransition = false

    /// Registers a matched-geometry anchor only when a promoted surface has a matching destination.
    var pairsRowWithPromotedSurface = true

    /// Allows drag, drop, and organization menus. Appearance previews disable this.
    var supportsOrganization = true

    /// Allows selecting multiple sidebar items for shared batch actions.
    var supportsMultiSelection = true

    var allowsMultiSelection: Bool { supportsOrganization && supportsMultiSelection }
}

extension EnvironmentValues {
    @Entry var browserInteractionCapabilities = BrowserInteractionCapabilities()
}
