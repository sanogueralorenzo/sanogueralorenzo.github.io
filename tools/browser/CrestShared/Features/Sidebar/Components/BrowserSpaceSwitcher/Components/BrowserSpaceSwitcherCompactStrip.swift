import SwiftUI

/// A centred, horizontally scrolling Space picker with the shell's accessories
/// held clear at either edge.
///
/// The picker gets an explicit viewport from the actual strip width and the
/// larger occupied utility side. Its segments keep their identity at the size
/// the person's icon sizing picks for that viewport, so overflow scrolls and
/// the active Space can always be revealed.
///
/// The sidebar toggle keeps to the window's edge and the lists to the page
/// side, where they fan out, whichever side the sidebar is docked on.
struct BrowserSpaceSwitcherCompactStrip: View {
    // MARK: - Variables

    let spaces: [BrowserSpaceIdentity]
    let selectedSpaceID: UUID
    let reorderState: BrowserSidebarReorderState
    let metrics: BrowserSpacePickerMetrics
    let iconSizing: BrowserSpaceIconSizing
    let chosenIconScale: Double
    let selectSpace: (UUID) -> Void
    let accessories: BrowserSpaceSwitcherAccessories
    let downloads: BrowserSpaceSwitcherDownloads

    @Environment(\.browserChromeAppearance) private var appearance
    @Environment(\.layoutDirection) private var layoutDirection

    /// The edge of the window the sidebar, and so this strip, stands against.
    private var sidebarEdge: HorizontalEdge {
        appearance.sidebarEdge(in: layoutDirection)
    }

    var body: some View {
        GeometryReader { geometry in
            let scale = fittedScale(
                in: BrowserSpaceSwitcherLayout.compactPickerViewportWidth(
                    availableWidth: geometry.size.width,
                    leadingUtilityWidth: utilityWidth(at: .leading),
                    trailingUtilityWidth: utilityWidth(at: .trailing)
                )
            )
            let style = CrestSpaceIconPickerStyle.compact.scaled(by: scale)
            let allocation = BrowserSpaceSwitcherLayout.compactStripAllocation(
                availableWidth: geometry.size.width,
                spaceCount: spaces.count,
                leadingUtilityWidth: utilityWidth(at: .leading),
                trailingUtilityWidth: utilityWidth(at: .trailing),
                style: style
            )

            ZStack {
                HStack(spacing: BrowserSpaceSwitcherLayout.compactStripSpacing) {
                    accessory(at: .leading)
                        .accessibilitySortPriority(
                            BrowserSpaceSwitcherLayout.leadingUtilityAccessibilityPriority
                        )

                    Spacer()

                    accessory(at: .trailing)
                        .accessibilitySortPriority(
                            BrowserSpaceSwitcherLayout.trailingUtilityAccessibilityPriority
                        )
                }
                .padding(
                    .horizontal,
                    BrowserSpaceSwitcherLayout.compactStripHorizontalInset
                )

                BrowserSpaceSwitcherCompactPicker(
                    spaces: spaces,
                    selectedSpaceID: selectedSpaceID,
                    reorderState: reorderState,
                    metrics: metrics.scaled(by: scale),
                    selectSpace: selectSpace,
                    allocation: allocation,
                    style: style
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(
            height: BrowserSpaceSwitcherLayout.compactStripHeight(
                for: .compact.scaled(by: iconSizing.largestScale(chosen: chosenIconScale))
            )
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Spaces")
    }

    // MARK: - Actions - Sizing

    /// The scale these Spaces are drawn at in a picker `width` wide.
    private func fittedScale(in width: CGFloat) -> CGFloat {
        iconSizing.scale(chosen: chosenIconScale, spaceCount: spaces.count, style: .compact, width: width)
    }

    // MARK: - Actions - Accessories

    /// The sidebar toggle on the sidebar's own edge, the lists on the other.
    @ViewBuilder
    private func accessory(at edge: HorizontalEdge) -> some View {
        if edge == sidebarEdge {
            if let sidebarToggle = accessories.sidebarToggle {
                toggleButton(sidebarToggle)
            }
        } else if let commonLists = accessories.commonLists {
            commonListsButton(commonLists)
        }
    }

    private func utilityWidth(at edge: HorizontalEdge) -> CGFloat {
        let isOccupied =
            edge == sidebarEdge
            ? accessories.sidebarToggle != nil
            : accessories.commonLists != nil
        return isOccupied ? BrowserSpaceSwitcherLayout.utilityButtonSize : 0
    }

    private func toggleButton(
        _ sidebarToggle: BrowserSpaceSwitcherSidebarToggle
    ) -> some View {
        Button(
            sidebarToggle.action.title,
            systemImage: appearance.sidebarOnRight ? "sidebar.right" : "sidebar.left",
            action: sidebarToggle.toggle
        )
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .frame(
            width: BrowserSpaceSwitcherLayout.utilityButtonSize,
            height: BrowserSpaceSwitcherLayout.utilityButtonSize
        )
        .accessibilityIdentifier("browser-sidebar-toggle")
        .help(sidebarToggle.action.title)
    }

    private func commonListsButton(
        _ commonLists: BrowserSpaceSwitcherCommonLists
    ) -> some View {
        BrowserSpaceSwitcherCommonListsButton(
            isExpanded: commonLists.isExpanded,
            downloads: downloads.items,
            newDownloads: downloads.newItems,
            badgeColor: downloads.badgeColor,
            action: commonLists.toggle,
            recordFrame: commonLists.recordTriggerFrame
        )
    }
}
