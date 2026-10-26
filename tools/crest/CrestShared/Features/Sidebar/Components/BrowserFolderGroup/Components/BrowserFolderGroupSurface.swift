import SwiftUI

/// The folder as one thing: its header, the rows it holds, the menu that acts
/// on it.
struct BrowserFolderGroupSurface: View {
    @Environment(BrowserSidebarInteractionState.self) private var sidebarInteraction

    let configuration: BrowserFolderGroupConfiguration
    let interaction: BrowserFolderGroupInteractionContext

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(BrowserGitHubIntegration.self) private var github: BrowserGitHubIntegration?

    private var folder: FolderStateModel { configuration.folder }

    private var dragItem: BrowserFolderDragItem { configuration.dragItem }

    var body: some View {
        VStack(spacing: 0) {
            BrowserFolderHeader(
                configuration: configuration,
                interaction: interaction
            )

            if !configuration.showsContents {
                BrowserFolderKeptRow(configuration: configuration, interaction: interaction)
            }
        }
        .contextMenu {
            if configuration.capabilities.supportsOrganization {
                if folder.source != nil, github != nil {
                    BrowserGitHubFolderOptionsMenu(configuration: configuration)
                    Divider()
                }
                BrowserFolderOrganizationMenu(
                    folder: folder,
                    context: configuration.context,
                    assignment: configuration.folderRuntimeAssignment,
                    createNestedFolder: interaction.beginCreatingChild,
                    renameFolder: interaction.beginRenaming,
                    deleteFolder: interaction.deleteFolder
                )
                .tint(.primary)
                // A long press opens this menu out of the same gesture that would
                // otherwise lift the folder. Telling the drag state the menu has
                // the press is what keeps the two from both claiming it.
                .onAppear {
                    sidebarInteraction.folderDragState.contextMenuDidOpen(
                        for: dragItem
                    )
                    // And the reorder state, which is where a touch lift lives and
                    // which no drag session will report back to once the menu has
                    // the press. See `yieldToCompetingInteraction`.
                    sidebarInteraction.sidebarReorderState
                        .yieldToCompetingInteraction()
                }
                .onDisappear {
                    sidebarInteraction.folderDragState.contextMenuDidClose(
                        for: dragItem
                    )
                }
            }
        }
        .animation(
            CrestMotion.collection.unlessReducingMotion(reduceMotion),
            value: folder.isCollapsed
        )
        .onAppear(perform: interaction.beginTitleEditingIfNeeded)
        .modifier(BrowserFolderCollapsedVisibilityUpdates(configuration: configuration, interaction: interaction))
        .onChange(of: interaction.editingFolderRequest.wrappedValue) { _, _ in
            interaction.beginTitleEditingIfNeeded()
        }
        .onChange(of: interaction.isTitleFocused.wrappedValue) { _, focused in
            if !focused,
                interaction.editingFolderRequest.wrappedValue
                    == configuration.folderRuntimeAssignment
            {
                interaction.commitTitle()
            }
        }
    }

}

/// macOS keeps visibility in the retained Space host; mobile retains its
/// existing row-local lifecycle. A lazy Mac row remount must not reset history.
private struct BrowserFolderCollapsedVisibilityUpdates: ViewModifier {
    let configuration: BrowserFolderGroupConfiguration
    let interaction: BrowserFolderGroupInteractionContext

    func body(content: Content) -> some View {
        #if os(macOS)
            content
                // Also supports isolated folder components in previews and
                // practice surfaces. Reconciliation is idempotent on remount;
                // the retained host updates folders while these views are absent.
                .onChange(of: interaction.isExpanded.wrappedValue, initial: true) { _, _ in reconcileVisibility() }
                .onChange(of: configuration.shownFolderTabID) { _, _ in reconcileVisibility() }
                .onChange(of: configuration.residencyRevision, initial: true) { _, _ in reconcileVisibility() }
        #else
            content
                .onChange(
                    of: interaction.isExpanded.wrappedValue,
                    initial: true
                ) { _, isExpanded in
                    interaction.collapsedTabVisibility.wrappedValue.expansionDidChange(
                        isExpanded: isExpanded,
                        selectedTabID: configuration.shownFolderTabID,
                        folderTabIDs: configuration.folderTabIDs
                    )
                }
                .onChange(of: configuration.shownFolderTabID) { _, selectedTabID in
                    interaction.collapsedTabVisibility.wrappedValue.selectionDidChange(
                        isExpanded: interaction.isExpanded.wrappedValue,
                        selectedTabID: selectedTabID,
                        folderTabIDs: configuration.folderTabIDs
                    )
                }
                .onChange(of: configuration.residencyRevision, initial: true) { _, _ in
                    interaction.collapsedTabVisibility.wrappedValue.residencyDidChange(
                        isExpanded: interaction.isExpanded.wrappedValue,
                        selectedTabID: configuration.shownFolderTabID,
                        residentFolderTabIDs: configuration.residentFolderTabIDs
                    )
                }
        #endif
    }

    #if os(macOS)
        private func reconcileVisibility() {
            guard configuration.context.space.folders.contains(configuration.folder.id)
            else { return }
            configuration.sidebarInteraction.reconcileCollapsedFolder(
                configuration.folderRuntimeAssignment, isExpanded: !configuration.folder.isCollapsed,
                selectedTabID: configuration.shownFolderTabID, folderTabIDs: configuration.folderTabIDs,
                residentFolderTabIDs: configuration.residentFolderTabIDs)
        }
    #endif
}
