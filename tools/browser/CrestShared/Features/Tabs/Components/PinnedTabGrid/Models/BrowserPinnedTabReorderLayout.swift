import CoreGraphics

/// The temporary pinned slots, shared by rendering and drop hit testing.
/// A lifted tile stays alive in the view tree but occupies no slot of its own.
struct BrowserPinnedTabReorderLayout: Equatable {
    // MARK: - Static Variables

    static let cellHeight: CGFloat = 47
    static let spacing = CrestSpacing.small

    // MARK: - Types

    enum Slot: Equatable {
        case tab(BrowserSidebarReorderItemID)
        case gap
    }

    // MARK: - Variables

    let ids: [BrowserSidebarReorderItemID]
    var liftedID: BrowserSidebarReorderItemID?
    var liftedIDs: Set<BrowserSidebarReorderItemID> = []
    var insertionIndex: Int?
    var availableWidth: CGFloat = BrowserChromeLayout.sidebarIdealWidth
    var preferredColumns = 0
    var fillsLastRow = false
    var tabScale = 1.0
    var tileHeight: CGFloat = Self.cellHeight
    var tileSpacing: CGFloat = Self.spacing
    var minimumTileWidth: CGFloat = BrowserSidebarDensity(1).pinMinimumWidth(touch: false)

    var slots: [Slot] {
        var result = ids.filter { $0 != liftedID && !liftedIDs.contains($0) }.map(Slot.tab)
        if let insertionIndex {
            result.insert(.gap, at: min(max(0, insertionIndex), result.count))
        }
        return result
    }

    var columns: Int {
        let automaticCapacity = Int(
            (Double(PinnedTabGridLayout.maximumColumns) / BrowserSidebarDensity(tabScale).scale).rounded())
        let requested = preferredColumns == 0 ? min(max(automaticCapacity, 1), 6) : min(max(preferredColumns, 1), 6)
        let width =
            availableWidth.isFinite ? min(max(0, availableWidth), 10_000) : BrowserChromeLayout.sidebarIdealWidth
        let fitting = max(1, Int((width + tileSpacing) / (minimumTileWidth + tileSpacing)))
        let capacity = min(requested, fitting)
        // A chosen count is what the person asked for, so rows fill to it.
        // Only the automatic layout balances rows, which can land below it.
        guard preferredColumns == 0 else { return min(max(slots.count, 1), capacity) }
        return PinnedTabGridLayout.columnCount(for: slots.count, maximumColumns: capacity)
    }

    var height: CGFloat {
        guard !slots.isEmpty else { return 0 }
        let rows = (slots.count + columns - 1) / columns
        return CGFloat(rows) * tileHeight + CGFloat(rows - 1) * tileSpacing
    }

    // MARK: - Actions - Layout

    func frame(for slot: Slot, in bounds: CGRect) -> CGRect? {
        let slots = slots
        guard let index = slots.firstIndex(of: slot) else { return nil }
        let columns = columns
        let lastRowFirstIndex = (slots.count - 1) / columns * columns
        // A short last row can share the full width instead of leaving empty cells.
        let tilesInRow = fillsLastRow && index >= lastRowFirstIndex ? slots.count - lastRowFirstIndex : columns
        let width = max(0, (bounds.width - CGFloat(tilesInRow - 1) * tileSpacing) / CGFloat(tilesInRow))
        return CGRect(
            x: bounds.minX + CGFloat(index % columns) * (width + tileSpacing),
            y: bounds.minY + CGFloat(index / columns) * (tileHeight + tileSpacing),
            width: width, height: tileHeight)
    }

    // MARK: - Actions - Preferences

    @MainActor
    func applyingPreferences(width: CGFloat, touch: Bool) -> Self {
        var value = self
        value.availableWidth = width.isFinite ? max(0, width) : BrowserChromeLayout.sidebarIdealWidth
        value.preferredColumns = Int(
            min(
                max(
                    BrowserSidebarDensityPreference.number(BrowserSidebarDensityPreference.pinColumnsKey, default: 0), 0
                ), 6))
        value.fillsLastRow = BrowserSidebarDensityPreference.defaults.bool(
            forKey: BrowserSidebarDensityPreference.pinsFillRowKey)
        let scale = BrowserSidebarDensityPreference.number(BrowserSidebarDensityPreference.scaleKey, default: 1)
        value.tabScale = scale
        value.tileHeight = BrowserSidebarDensity(scale).pinHeight(touch: touch)
        value.tileSpacing = BrowserSidebarDensity(scale).pinSpacing
        value.minimumTileWidth = BrowserSidebarDensity(scale).pinMinimumWidth(touch: touch)
        return value
    }
}
