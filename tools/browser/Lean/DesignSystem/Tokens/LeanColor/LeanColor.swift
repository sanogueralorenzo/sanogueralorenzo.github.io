import SwiftUI

/// Semantic colors for Lean-authored chrome. Space identity colors remain data-driven.
enum LeanColor {
    static let hover = Color.primary.opacity(LeanOpacity.hover)
    static let selectedBorder = Color.primary.opacity(LeanOpacity.selectedBorder)
}
