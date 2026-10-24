import SwiftUI

/// Touch keeps the capsule appearance, using the same progress-driven buttons
/// and clear overflow controls as the compact desktop lane.
struct BrowserSpaceSwitcherScrollingSegments: View {
    // MARK: - Variables

    let spaces: [BrowserSpaceIdentity]
    let selectedSpaceID: UUID
    let reorderState: BrowserSidebarReorderState
    let metrics: BrowserSpacePickerMetrics
    let iconSizing: BrowserSpaceIconSizing
    let chosenIconScale: Double
    let selectSpace: (UUID) -> Void

    // MARK: - Actions - Drawing

    var body: some View {
        GeometryReader { geometry in
            let scale = iconSizing.scale(
                chosen: chosenIconScale, spaceCount: spaces.count, style: .touch, width: geometry.size.width)
            let style = CrestSpaceIconPickerStyle.touch.scaled(by: scale)
            let allocation = BrowserSpaceSwitcherCompactAllocation(
                pickerViewportWidth: geometry.size.width,
                pickerContentWidth: style.contentWidth(spaceCount: spaces.count),
                overflowButtonWidth: style.overflowButtonWidth)
            BrowserSpaceSwitcherCompactPicker(
                spaces: spaces, selectedSpaceID: selectedSpaceID,
                reorderState: reorderState, metrics: metrics.scaled(by: scale), selectSpace: selectSpace,
                allocation: allocation, style: style)
        }
        .frame(
            height: CrestSpaceIconPickerStyle.touch.scaled(
                by: iconSizing.largestScale(chosen: chosenIconScale)
            ).height
        )
        .padding(.horizontal, BrowserSpaceSwitcherLayout.scrollingTrackHorizontalInset)
        .padding(.top, BrowserSpaceSwitcherLayout.scrollingTrackTopInset)
    }
}
