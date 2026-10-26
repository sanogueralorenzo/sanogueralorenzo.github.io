import SwiftUI

/// Semantic colors for Crest-authored chrome. Space identity colors remain data-driven.
enum CrestColor {
    static let selection = Color.primary.opacity(CrestOpacity.selection)
    static let chromeSurface = Color.primary.opacity(CrestOpacity.chromeSurface)
    static let hover = Color.primary.opacity(CrestOpacity.hover)
    static let subtleBorder = Color.primary.opacity(CrestOpacity.border)
    static let selectedBorder = Color.primary.opacity(CrestOpacity.selectedBorder)
    static let dropIndicator = CrestBrandPalette.paper.opacity(CrestOpacity.dropIndicator)
    static let textPrimary = Color.primary
    static let textSecondary = Color.secondary

    /// The platform's own window background, under a Space's colors.
    #if os(macOS)
        static let windowBackground = Color(nsColor: .windowBackgroundColor)
    #else
        static let windowBackground = Color(uiColor: .systemBackground)
    #endif
}
