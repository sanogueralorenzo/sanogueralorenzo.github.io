import SwiftUI

struct PinnedTabGridContent: View {
    /// The width of the drop target that trails the last pinned tile.
    private static let trailingTargetWidth = CrestSpacing.extraLarge

    @Environment(BrowserSidebarInteractionState.self) private var sidebarInteraction: BrowserSidebarInteractionState?
    let grid: PinnedTabGrid

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var renamingAssignment: BrowserTabRuntimeAssignment?
    @State private var iconRequest: BrowserTabRuntimeAssignment?
    @State private var draftTitle = ""
    private var tabScale: Double { BrowserDeviceAppearanceStore.shared.tabScale }
    private var pinColumns: Int { BrowserDeviceAppearanceStore.shared.pinColumns }

    private var tabs: [TabStateModel] { grid.tabs }
    private var assignment: BrowserSpaceRuntimeAssignment { grid.assignment }
    private var capabilities: BrowserInteractionCapabilities { grid.capabilities }
    private var browser: BrowserStore? { grid.context?.browser }

    private var reorderContext: BrowserSidebarReorderContext? {
        guard
            capabilities.supportsOrganization,
            let context = grid.context,
            let sidebarInteraction
        else { return nil }
        return BrowserSidebarReorderContext(
            browser: context.browser,
            spaceAccess: context.spaceAccess,
            state: sidebarInteraction.sidebarReorderState
        )
    }

    var body: some View {
        BrowserPinnedTabSlotLayout(projection: projection) {
            ForEach(tabs, id: \.id) { tab in
                PinnedTabTile(
                    tab: tab, grid: grid, reorder: reorderContext, iconRequest: $iconRequest,
                    renameTab: { beginRenaming(tab) }
                )
            }
            RoundedRectangle(cornerRadius: BrowserSidebarMetrics.layerCornerRadius(), style: .continuous)
                .fill(.primary.opacity(0.035))
                .overlay {
                    RoundedRectangle(cornerRadius: BrowserSidebarMetrics.layerCornerRadius(), style: .continuous)
                        .strokeBorder(.primary.opacity(0.12), lineWidth: 0.5)
                }
                .opacity(projection.insertionIndex == nil ? 0 : 1)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .animation(
            CrestMotion.dragSource.unlessReducingMotion(reduceMotion),
            value: projection.slots
        )
        .environment(\.browserInteractionCapabilities, capabilities)
        .crestCollectionMotion(ids: tabs.map(\.id))
        .overlay(alignment: .trailing) {
            if reorderContext != nil, let dragState = grid.dragState, dragState.item != nil {
                Color.clear
                    .frame(width: Self.trailingTargetWidth)
                    .frame(maxHeight: .infinity)
                    .contentShape(.rect)
                    .accessibilityHidden(true)
            }
        }
        .alert("Rename Tab", isPresented: isRenamingBinding) {
            TextField("Tab Name", text: $draftTitle)
                .accessibilityIdentifier("tab-rename-field")

            Button("Rename", action: commitRename)
                .accessibilityIdentifier("confirm-rename-tab")

            Button("Cancel", role: .cancel) { renamingAssignment = nil }
        }
        .onChange(of: renamingAssignmentIsLive) { _, isLive in
            guard !isLive else { return }
            renamingAssignment = nil
        }
        .onChange(of: iconRequestIsLive) { _, isLive in
            guard !isLive else { return }
            iconRequest = nil
        }
        .onChange(of: assignment) { _, _ in iconRequest = nil }
        .onDisappear { iconRequest = nil }
    }

    private var iconRequestIsLive: Bool {
        guard let iconRequest, iconRequest.spaceID == assignment.spaceID,
            iconRequest.profileID == assignment.profileID, capabilities.supportsOrganization,
            let context = grid.context
        else { return false }
        return BrowserTabOrganizationAction(browser: context.browser, spaceAccess: context.spaceAccess)
            .canCustomizePinnedIcon(for: iconRequest)
    }

    /// A pinned tile shows an icon and no editable label, so renaming one asks
    /// for the name instead of editing in place the way a sidebar row does.
    private var isRenamingBinding: Binding<Bool> {
        Binding(
            get: { renamingAssignmentIsLive },
            set: { isPresented in
                guard !isPresented else { return }
                renamingAssignment = nil
            }
        )
    }

    private func beginRenaming(_ tab: TabStateModel) {
        let assignment = runtimeAssignment(for: tab.id)
        guard isCurrentAndUnlocked(assignment) else { return }
        draftTitle = tab.shownTitle
        renamingAssignment = assignment
    }

    private func commitRename() {
        guard let renamingAssignment else { return }
        self.renamingAssignment = nil
        guard let browser,
            isCurrentAndUnlocked(renamingAssignment)
        else { return }
        let draftTitle = draftTitle
        browser.setTabCustomTitle(
            draftTitle,
            for: renamingAssignment.tabID,
            matching: BrowserSpaceRuntimeAssignment(
                spaceID: renamingAssignment.spaceID,
                profileID: renamingAssignment.profileID
            )
        )
    }

    private var projection: BrowserPinnedTabReorderLayout {
        let ids = tabs.map { BrowserSidebarReorderItemID.tab($0.id) }
        var value =
            (reorderContext?.state.pinnedLayout(ids: ids, in: assignment) ?? BrowserPinnedTabReorderLayout(ids: ids))
            .applyingPreferences(width: BrowserChromeLayout.sidebarIdealWidth, touch: capabilities.supportsTouch)
        value.preferredColumns = min(max(pinColumns, 0), 6)
        value.fillsLastRow = BrowserDeviceAppearanceStore.shared.pinsFillRow
        value.tabScale = tabScale
        value.tileHeight = BrowserSidebarDensity(tabScale).pinHeight(touch: capabilities.supportsTouch)
        value.tileSpacing = BrowserSidebarDensity(tabScale).pinSpacing
        return value
    }

    private var renamingAssignmentIsLive: Bool {
        guard let renamingAssignment else { return false }
        return isCurrentAndUnlocked(renamingAssignment)
    }

    private func isCurrentAndUnlocked(
        _ assignment: BrowserTabRuntimeAssignment
    ) -> Bool {
        grid.context?.isTabCurrent(assignment) ?? false
    }

    private func runtimeAssignment(
        for tabID: UUID
    ) -> BrowserTabRuntimeAssignment {
        BrowserTabRuntimeAssignment(
            tabID: tabID,
            spaceID: assignment.spaceID,
            profileID: assignment.profileID
        )
    }
}
