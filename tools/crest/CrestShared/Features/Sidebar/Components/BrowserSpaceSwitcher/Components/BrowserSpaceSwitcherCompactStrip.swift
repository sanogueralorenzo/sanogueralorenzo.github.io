import SwiftUI

/// A trailing-aligned, horizontally scrolling Space picker with overflow controls.
struct BrowserSpaceSwitcherCompactStrip: View {
    // MARK: - Variables

    let spaces: [BrowserSpaceIdentity]
    let selectedSpaceID: UUID
    let reorderState: BrowserSidebarReorderState
    let metrics: BrowserSpacePickerMetrics
    let selectSpace: (UUID) -> Void
    var commands: (BrowserSpaceIdentity) -> [CrestSpaceChipCommand] = { _ in [] }

    // MARK: - Actions - Drawing

    var body: some View {
        GeometryReader { geometry in
            let style = CrestSpaceIconPickerStyle.titlebar
            let contentWidth = style.contentWidth(spaceCount: spaces.count)
            let allocation = BrowserSpaceSwitcherCompactAllocation(
                pickerViewportWidth: min(geometry.size.width, contentWidth),
                pickerContentWidth: contentWidth,
                overflowButtonWidth: style.overflowButtonWidth)

            BrowserSpaceSwitcherCompactPicker(
                spaces: spaces,
                selectedSpaceID: selectedSpaceID,
                reorderState: reorderState,
                metrics: metrics,
                selectSpace: selectSpace,
                commands: commands,
                allocation: allocation,
                style: style
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        }
        .frame(height: CrestSpaceIconPickerStyle.titlebar.height)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Spaces")
    }
}
