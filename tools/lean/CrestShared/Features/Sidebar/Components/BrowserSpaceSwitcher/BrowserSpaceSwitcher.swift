import SwiftUI

/// The Space selector, arranged for the shell's input size.
struct BrowserSpaceSwitcher: View {
    // MARK: - Variables

    @Environment(BrowserSidebarInteractionState.self) private var sidebarInteraction

    let browser: BrowserStore

    let capabilities: BrowserInteractionCapabilities
    let selectSpace: (UUID) -> Void
    var commands: (BrowserSpaceIdentity) -> [CrestSpaceChipCommand] = { _ in [] }

    // MARK: - Actions - Drawing

    var body: some View {
        switch capabilities.spaceSwitcherArrangement {
        case .compactStrip:
            BrowserSpaceSwitcherCompactStrip(
                spaces: spaces,
                selectedSpaceID: selectedSpaceID,
                reorderState: sidebarInteraction.sidebarReorderState,
                metrics: metrics,
                selectSpace: selectSpace, commands: commands
            )
        case .scrollingSegments:
            BrowserSpaceSwitcherScrollingSegments(
                spaces: spaces,
                selectedSpaceID: selectedSpaceID,
                reorderState: sidebarInteraction.sidebarReorderState,
                metrics: metrics,
                selectSpace: selectSpace, commands: commands
            )
        }
    }

    private var spaces: [BrowserSpaceIdentity] {
        browser.availableSpaces.map(BrowserSpaceIdentity.init(space:))
    }

    private var selectedSpaceID: UUID {
        browser.selectedSpaceID
    }

    private var metrics: BrowserSpacePickerMetrics {
        capabilities.spacePickerMetrics
    }
}
