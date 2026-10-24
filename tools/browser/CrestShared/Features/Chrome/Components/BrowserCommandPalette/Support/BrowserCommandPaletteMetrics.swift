import CoreGraphics

enum BrowserCommandPaletteMetrics {
    static let maximumResultAreaHeight: CGFloat = 390
    static let resultOuterPadding: CGFloat = 28
    static let resultRowHeight: CGFloat = 54
    static let resultRowSpacing: CGFloat = 6
    static let resultHeaderHeight: CGFloat = 17
    static let resultSectionSpacing: CGFloat = 16

    static let overlayCardPadding: CGFloat = 24
    static var overlayReservedHeight: CGFloat {
        (overlayCardPadding * 2)
            + searchFieldMinimumHeight
            + CrestLayout.hairline
    }
    static let minimumOverlayResultHeight: CGFloat = 82
    static let maximumCardWidth: CGFloat = 720
    static let cardCornerRadius: CGFloat = 26
    /// How far below full size the card's contents start while the card grows
    /// out of the address field, and end while it shrinks back.
    static let morphContentScale: CGFloat = 0.97

    static let searchFieldSpacing: CGFloat = 12
    static let searchFieldHorizontalPadding: CGFloat = 20
    static let searchFieldMinimumHeight: CGFloat = 68

    static let resultContentPadding: CGFloat = 14
    /// The row of search provider chips under the field.
    static let providerChipRowHeight: CGFloat = 44
    /// A provider's logo in a chip, and the neutral plate it sits on so it
    /// reads on any brand tint.
    static let chipIconSize: CGFloat = 14
    static let chipIconPlateSize: CGFloat = 20
    static let resultGroupSpacing: CGFloat = 16
    static let resultHeaderSpacing: CGFloat = 6
    static let resultHeaderHorizontalPadding: CGFloat = 4

    static let rowSpacing: CGFloat = 12
    static let rowTextSpacing: CGFloat = 2
    static let rowHorizontalPadding: CGFloat = 12
    static let rowCornerRadius: CGFloat = 12
    static let selectedRowOpacity = 0.16
    static let restingRowOpacity = 0.045

    static let rowIconContainerSize: CGFloat = 34
    static let rowFaviconSize: CGFloat = 20
    static let rowSymbolPointSize: CGFloat = 16
    static let intentSymbolPointSize: CGFloat = 18
    static let rowIconCornerRadius: CGFloat = 8
    static let rowIconBackgroundOpacity = 0.08

    static let shortcutHorizontalPadding: CGFloat = 6
    static let shortcutMinimumHeight: CGFloat = 20
    static let shortcutCornerRadius: CGFloat = 5
    static let shortcutBackgroundOpacity = 0.07

    static let scrimOpacity = 0.18
}
