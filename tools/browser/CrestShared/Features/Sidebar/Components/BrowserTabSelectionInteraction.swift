import SwiftUI

/// Selection uses the live control bounds, not the resting frames frozen by a drag.
struct BrowserTabSelectionTarget: ViewModifier {
    let tabID: UUID?
    let browser: BrowserStore?
    let assignment: BrowserSpaceRuntimeAssignment
    var isEnabled = true
    var folderID: UUID? = nil
    @Environment(\.browserInteractionCapabilities) private var capabilities

    func body(content: Content) -> some View {
        content.modifier(
            BrowserPlatformTabSelectionTarget(
                itemID: folderID.map(BrowserSelectionItemID.folder) ?? tabID.map(BrowserSelectionItemID.tab),
                browser: browser,
                assignment: assignment,
                isEnabled: isEnabled && capabilities.allowsMultiSelection
            )
        )
    }
}

/// Selection belongs to the activation button, never its close control.
struct BrowserTabSelectionAccessibility: ViewModifier {
    let tabID: UUID
    let spaceID: UUID
    let browser: BrowserStore?
    let isActive: Bool
    let isLoaded: Bool

    private var selected: Bool { browser?.tabMultiSelection.contains(tabID) == true }

    func body(content: Content) -> some View {
        content
            .accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityValue(value)
            .modifier(BrowserSidebarSelectionAccessibilityActions(item: .tab(tabID), browser: browser))
    }

    /// The tab's state, with the engine its page runs on when its icon wears
    /// that engine's badge, which says nothing itself.
    private var value: String {
        var parts = [BrowserChromeAccessibility.tabValue(isLoaded: isLoaded)]
        if isActive { parts.append(String(localized: "Active page")) }
        if selected { parts.append(String(localized: "Selected for tab actions")) }
        if let engine = browser?.core.state.engineBadge(forTab: tabID) {
            parts.append(String(localized: engine.pageDescription))
        }
        return parts.joined(separator: ", ")
    }
}

struct BrowserFolderSelectionAccessibility: ViewModifier {
    let folderID: UUID
    let browser: BrowserStore
    private var selected: Bool { browser.tabMultiSelection.contains(.folder(folderID)) }
    func body(content: Content) -> some View {
        content.accessibilityAddTraits(selected ? .isSelected : [])
            .modifier(BrowserSidebarSelectionAccessibilityActions(item: .folder(folderID), browser: browser))
    }
}

private struct BrowserSidebarSelectionAccessibilityActions: ViewModifier {
    @Environment(BrowserSidebarInteractionState.self) private var sidebarInteraction: BrowserSidebarInteractionState?

    let item: BrowserSelectionItemID
    let browser: BrowserStore?
    @Environment(\.browserInteractionCapabilities) private var capabilities

    @ViewBuilder
    func body(content: Content) -> some View {
        if capabilities.allowsMultiSelection, let browser, sidebarInteraction != nil {
            content
                .accessibilityAction(
                    named: browser.tabMultiSelection.contains(item) ? "Remove from Selection" : "Add to Selection"
                ) {
                    browser.tabMultiSelection.click(
                        item,
                        units: BrowserSidebarSelection.itemUnits(in: browser), command: true)
                }
                .accessibilityAction(named: "Select Range to Here") {
                    browser.tabMultiSelection.click(
                        item,
                        units: BrowserSidebarSelection.itemUnits(in: browser), command: true, shift: true,
                        activeItem: browser.selectedTabID(in: browser.selectedSpaceID).map(BrowserSelectionItemID.tab))
                }
        } else {
            content
        }
    }
}
