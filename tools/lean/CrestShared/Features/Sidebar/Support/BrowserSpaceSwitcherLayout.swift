import CoreGraphics
import Foundation

/// Shared Space picker sizing and overflow allocation.
enum BrowserSpaceSwitcherLayout {
    static let overflowButtonWidth = CrestSpaceIconPickerMetrics.overflowButtonWidth

    /// The band the compact pointer picker occupies.
    static let compactStripHeight: CGFloat = 50

    /// The inset that keeps the compact strip in the same column as the rows
    /// above it.
    static let compactStripHorizontalInset: CGFloat = 12

    static let pickerAccessibilityPriority: Double = 2

    /// The inset that lines the scrolling track up with the sidebar's rows,
    /// and the gap between it and the chrome above.
    static let scrollingTrackHorizontalInset: CGFloat = 12
    static let scrollingTrackTopInset: CGFloat = 6

    /// Resolves the compact picker's viewport and content width.
    static func compactStripAllocation(
        availableWidth: CGFloat,
        spaceCount: Int,
        style: CrestSpaceIconPickerStyle = .compact
    ) -> BrowserSpaceSwitcherCompactAllocation {
        BrowserSpaceSwitcherCompactAllocation(
            pickerViewportWidth: compactPickerViewportWidth(
                availableWidth: availableWidth
            ),
            pickerContentWidth: style.contentWidth(spaceCount: max(0, spaceCount)),
            overflowButtonWidth: style.overflowButtonWidth
        )
    }

    /// The width available to the picker after its horizontal insets.
    static func compactPickerViewportWidth(availableWidth: CGFloat) -> CGFloat {
        max(0, availableWidth - 2 * compactStripHorizontalInset)
    }

    /// The active Space is the semantic scroll target. Falling back to the
    /// first surviving identity keeps a transient removal repair navigable
    /// without introducing a second selection model in the view.
    static func compactScrollTarget(
        spaceIDs: [UUID],
        selectedSpaceID: UUID
    ) -> UUID? {
        guard !spaceIDs.isEmpty else { return nil }
        return spaceIDs.contains(selectedSpaceID)
            ? selectedSpaceID
            : spaceIDs.first
    }

}

struct BrowserSpaceSwitcherCompactAllocation: Equatable, Sendable {
    let pickerViewportWidth: CGFloat
    let pickerContentWidth: CGFloat
    var overflowButtonWidth: CGFloat = BrowserSpaceSwitcherLayout.overflowButtonWidth

    var usesOverflow: Bool {
        pickerContentWidth > pickerViewportWidth
    }

    var scrollViewportWidth: CGFloat {
        max(0, pickerViewportWidth - (usesOverflow ? 2 * overflowButtonWidth : 0))
    }

}
