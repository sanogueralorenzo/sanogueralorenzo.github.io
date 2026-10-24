/// When a pointer event is allowed to move Split View focus.
///
/// The two inputs that carry focus into the layout — an `NSTrackingArea` entering
/// a card and a local `NSEvent` monitor seeing a mouse-down inside one — are both
/// AppKit machinery that no unit test can drive. What *is* testable is the guard
/// set they consult, so it lives here as pure arithmetic over booleans and both
/// callers do nothing but ask.
///
/// The guards exist for these reasons:
///
/// - **Already focused.** Refocusing the focused card would push a redundant
///   selection through the store on every pointer entry.
/// - **Address editing** (hover only). Focus *is* selection, and the selection
///   observer resigns address focus, so a pointer drifting over a neighbour while
///   someone types a URL would silently discard what they typed. A deliberate
///   click is different: it is a decision to leave the address field.
/// - **A drag in flight.** A lifted sidebar item crossing the content area is
///   about to resolve its own target; focus must not follow the pointer that is
///   carrying it.
/// - **A card in flight.** A carried card crosses every neighbour on its way to
///   a new slot, and the card that already took focus at the pickup is the one
///   somebody is holding. Focus arriving at each column it passes over would
///   reselect the split several times per gesture.
/// - **The command palette.** The palette is modal over the content area. A click
///   that lands on it, or a pointer crossing beneath it, is not addressed to a
///   card.
extension BrowserSplitPageSurface {
    // MARK: - Actions - Focus

    /// Whether a pointer entering an unfocused card should focus it.
    nonisolated static func focusesOnHover(
        followsMouse: Bool,
        isCardFocused: Bool,
        isAddressEditing: Bool,
        isDraggingSidebarItem: Bool,
        isCarryingCard: Bool,
        isCommandPalettePresented: Bool
    ) -> Bool {
        guard followsMouse else { return false }
        return !isCardFocused
            && !isAddressEditing
            && !isDraggingSidebarItem
            && !isCarryingCard
            && !isCommandPalettePresented
    }

    /// Whether a mouse-down inside an unfocused card should focus it.
    ///
    /// Independent of the Follow Mouse preference: click-to-focus is how Split
    /// View works, not a behaviour to opt into.
    ///
    /// A carry keeps its own mouse events, so in practice no click arrives while
    /// one is in flight — but the guard is stated rather than assumed, because
    /// "no click can reach here" is a property of a different file.
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
