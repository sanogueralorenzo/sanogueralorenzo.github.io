import SwiftUI

/// Semantic colors for Browser-authored chrome. Space identity colors remain data-driven.
enum BrowserColor {
    static let hover = Color.primary.opacity(BrowserOpacity.hover)
    static let selectedBorder = Color.primary.opacity(BrowserOpacity.selectedBorder)
}
