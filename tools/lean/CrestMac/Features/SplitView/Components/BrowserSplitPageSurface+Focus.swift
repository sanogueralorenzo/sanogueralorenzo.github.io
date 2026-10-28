/// Conditions for a deliberate click to select a Split View card.
extension BrowserSplitPageSurface {
    // MARK: - Actions - Focus

    /// A click leaves the current selection alone during a drag or while the
    /// command palette owns input.
    nonisolated static func focusesOnClick(
        isCardFocused: Bool,
        isDraggingSidebarItem: Bool,
        isCarryingCard: Bool,
        isCommandPalettePresented: Bool
    ) -> Bool {
        !isCardFocused
            && !isDraggingSidebarItem
            && !isCarryingCard
            && !isCommandPalettePresented
    }
}
