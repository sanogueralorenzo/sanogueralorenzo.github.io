/// Shared opacity roles for custom interaction and accessibility states.
enum CrestOpacity {
    static let brandHairline = 0.18
    static let dropIndicator = 0.72
    static let hover = 0.08
    static let interactionSelection = 0.13
    static let interactionSelectionBorder = 0.10
    static let interactionSelectionShadow = 0.08
    static let selection = interactionSelection
    static let chromeSurface = 0.055
    static let selectedSurface = selection
    static let border = 0.12
    static let selectedBorder = interactionSelectionBorder
    static let disabled = 0.5
    /// Disabled chrome glyphs remain visible against both page and sidebar glass.
    static let controlDisabledForeground = 0.48
    static let controlShadow = 0.16
    /// A status drawn across a sidebar row, under its title.
    static let statusSurface = 0.35
    /// A status drawn across a pinned tile, which is small and sits on its
    /// own plate.
    static let prominentStatusSurface = 0.6
}
