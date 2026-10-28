import CoreGraphics

/// Geometry of the slots a section lays its rows out in, and how far a row
/// steps aside to open the gap a lift would land in.
enum BrowserSidebarReorderSlotLayout: Equatable, Sendable {
    /// One column; rows step vertically by `stride`.
    case list(stride: CGFloat)
    /// Reading-order grid; cells step by `columnStride` across and
    /// `rowStride` down, wrapping every `columns` cells.
    case grid(columns: Int, columnStride: CGFloat, rowStride: CGFloat)

    // MARK: - Static Variables

    /// Gap the lifted row leaves behind, as a fraction of its own height.
    static let displacementFraction: CGFloat = 1

    // MARK: - Initializers

    /// Derives slot geometry from the measured rows, so spacing and column count
    /// come from the real layout rather than being duplicated here.
    init(rows orderedRows: [BrowserSidebarReorderRow], fallbackStride: CGFloat) {
        let usesGrid = orderedRows.first?.usesGridOrdering ?? false
        guard usesGrid else {
            // Every row crossing the gap fills the slot left by the lifted row.
            // A list may mix ordinary tabs with taller Split View groups, so a
            // neighbouring row's pitch is not the size of that vacant slot.
            self = .list(stride: fallbackStride)
            return
        }

        guard let firstRow = orderedRows.first else {
            self = .list(stride: fallbackStride)
            return
        }
        let firstLine = orderedRows.filter { $0.frame.minY == firstRow.frame.minY }
        let columns = max(firstLine.count, 1)
        let columnStride = Self.stride(
            ofPitches: Self.horizontalPitches(firstLine),
            fallback: firstRow.frame.width
        )
        let rowStride = Self.stride(
            ofPitches: Self.verticalPitches(orderedRows),
            fallback: firstRow.frame.height
        )
        self = .grid(
            columns: columns,
            columnStride: columnStride,
            rowStride: rowStride
        )
    }

    // MARK: - Actions - Displacement

    /// How far a row steps aside to open the gap at `insertionIndex`.
    ///
    /// Rows keep their original layout slots while a drag is in flight — only the
    /// lifted row is offset — so displacement is the difference between the slot
    /// a row currently occupies and the slot it should occupy once the gap is
    /// open. Both are expressed in "list with the lifted row removed" index
    /// space, the same space `insertionIndex` is computed in.
    ///
    /// - Parameters:
    ///   - candidateIndex: the row's index among rows excluding the lifted one.
    ///   - draggedSlot: the lifted row's index in the full, unfiltered list.
    func displacement(
        candidateIndex: Int,
        draggedSlot: Int,
        insertionIndex: Int
    ) -> CGSize {
        let currentSlot =
            candidateIndex < draggedSlot ? candidateIndex : candidateIndex + 1
        let desiredSlot =
            candidateIndex < insertionIndex ? candidateIndex : candidateIndex + 1
        guard currentSlot != desiredSlot else { return .zero }

        switch self {
        case .list(let stride):
            let steps = CGFloat(desiredSlot - currentSlot)
            return CGSize(width: 0, height: steps * stride * Self.displacementFraction)
        case .grid(let columns, let columnStride, let rowStride):
            guard columns > 0 else { return .zero }
            let currentColumn = currentSlot % columns
            let currentRow = currentSlot / columns
            let desiredColumn = desiredSlot % columns
            let desiredRow = desiredSlot / columns
            return CGSize(
                width: CGFloat(desiredColumn - currentColumn) * columnStride,
                height: CGFloat(desiredRow - currentRow) * rowStride
            )
        }
    }

    private static func verticalPitches(
        _ rows: [BrowserSidebarReorderRow]
    ) -> [CGFloat] {
        zip(rows, rows.dropFirst()).map { abs($1.frame.minY - $0.frame.minY) }
    }

    private static func horizontalPitches(
        _ rows: [BrowserSidebarReorderRow]
    ) -> [CGFloat] {
        zip(rows, rows.dropFirst()).map { abs($1.frame.minX - $0.frame.minX) }
    }

    private static func stride(
        ofPitches pitches: [CGFloat],
        fallback: CGFloat
    ) -> CGFloat {
        let positive = pitches.filter { $0 > 0 }
        return positive.min() ?? fallback
    }
}
