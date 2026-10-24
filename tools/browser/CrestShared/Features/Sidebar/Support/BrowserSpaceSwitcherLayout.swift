import CoreGraphics
import Foundation

/// Shared Space picker sizing and the lane reserved between sidebar utilities.
enum BrowserSpaceSwitcherLayout {
    static let utilityButtonSize: CGFloat = 32
    static let overflowButtonWidth = CrestSpaceIconPickerMetrics.overflowButtonWidth

    /// The band the compact strip occupies, which is what holds the picker
    /// clear of the sidebar's bottom edge and the utilities either side of it.
    static let compactStripHeight: CGFloat = 50

    /// The inset that keeps the compact strip in the same column as the rows
    /// above it.
    static let compactStripHorizontalInset: CGFloat = 12

    /// The gap between the strip's utilities and the picker between them.
    static let compactStripSpacing: CGFloat = 2

    /// VoiceOver follows the same leading-to-trailing order users see even
    /// though the centred picker is composed in a `ZStack`.
    static let leadingUtilityAccessibilityPriority: Double = 3
    static let pickerAccessibilityPriority: Double = 2
    static let trailingUtilityAccessibilityPriority: Double = 1

    /// The inset that lines the scrolling track up with the sidebar's rows,
    /// and the gap between it and the chrome above.
    static let scrollingTrackHorizontalInset: CGFloat = 12
    static let scrollingTrackTopInset: CGFloat = 6

    /// Resolves the compact picker's centred viewport inside the utility
    /// buttons that flank it, and how much of it Spaces drawn in `style` take.
    static func compactStripAllocation(
        availableWidth: CGFloat,
        spaceCount: Int,
        leadingUtilityWidth: CGFloat,
        trailingUtilityWidth: CGFloat,
        style: CrestSpaceIconPickerStyle = .compact
    ) -> BrowserSpaceSwitcherCompactAllocation {
        BrowserSpaceSwitcherCompactAllocation(
            pickerViewportWidth: compactPickerViewportWidth(
                availableWidth: availableWidth,
                leadingUtilityWidth: leadingUtilityWidth,
                trailingUtilityWidth: trailingUtilityWidth
            ),
            pickerContentWidth: style.contentWidth(spaceCount: max(0, spaceCount)),
            overflowButtonWidth: style.overflowButtonWidth
        )
    }

    /// The width the compact picker has between the utility buttons.
    ///
    /// The larger utility side is reserved on both sides. That keeps the
    /// picker centred when one accessory is absent or wider, while the actual
    /// leading and trailing widths still determine the no-overlap edges.
    static func compactPickerViewportWidth(
        availableWidth: CGFloat,
        leadingUtilityWidth: CGFloat,
        trailingUtilityWidth: CGFloat
    ) -> CGFloat {
        let width = max(0, availableWidth)
        let leadingWidth = max(0, leadingUtilityWidth)
        let trailingWidth = max(0, trailingUtilityWidth)
        let leadingReservation = utilityReservation(for: leadingWidth)
        let trailingReservation = utilityReservation(for: trailingWidth)
        let balancedSideReservation = max(
            leadingReservation,
            trailingReservation
        )
        let contentWidth = max(0, width - 2 * compactStripHorizontalInset)
        return max(
            0,
            contentWidth - 2 * balancedSideReservation
        )
    }

    /// The band a compact strip with its track drawn in `style` occupies:
    /// the usual band, grown by as much as a larger track grows, so the track
    /// never comes closer to the window's edge than the usual one does.
    static func compactStripHeight(for style: CrestSpaceIconPickerStyle) -> CGFloat {
        compactStripHeight + max(0, style.height - CrestSpaceIconPickerStyle.compact.height)
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

    private static func utilityReservation(for width: CGFloat) -> CGFloat {
        width > 0 ? width + compactStripSpacing : 0
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
