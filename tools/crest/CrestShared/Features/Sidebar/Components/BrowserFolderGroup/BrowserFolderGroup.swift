import SwiftUI

/// One folder in the sidebar — its header and the rows it holds — on every
/// shell.
///
/// The group owns the state a folder has to keep between events: which
/// deferred action a menu asked for, and which tab a collapsed folder is still
/// showing. Everything a part needs to draw arrives as
/// `BrowserFolderGroupConfiguration`; everything a part may do arrives as
/// `BrowserFolderGroupInteractionContext`. What the folder holds is the list
/// the core publishes for its inside, drawn only while the folder is open, so
/// a collapse redraws this group alone.
///
/// A folder's menu actions outlive the menu that asked for them, so each is
/// held as the folder it was asked for rather than as a bare flag, and every
/// one of them is re-checked against the live Space before it runs. A Space
/// can be reselected, relocked, or have the folder deleted out from under an
/// open colour popover, and a request that can no longer be honoured is
/// dropped instead of landing on whatever took its place.
struct BrowserFolderGroup: View {
    @Environment(BrowserSidebarInteractionState.self) private var sidebarInteraction

    let folder: FolderStateModel
    /// How many folders hold this one.
    let depth: Int
    let context: BrowserSidebarListContext
    /// The tab a collapsed folder around this one keeps on screen, which this
    /// folder shows in place of its contents.
    var inheritedKeptTabID: UUID? = nil

    @Environment(\.sidebarSpacePresentation) private var spacePresentation
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var draftTitle = ""
    @State private var iconRequest: BrowserFolderRuntimeAssignment?
    @State private var colorRequest: BrowserFolderRuntimeAssignment?
    @State private var deletionRequest: BrowserFolderRuntimeAssignment?
    #if os(macOS)
        private var collapsedTabVisibility: BrowserCollapsedFolderTabVisibilityState {
            get { collapsedVisibilityOwner.state }
            nonmutating set { collapsedVisibilityOwner.state = newValue }
        }

        private var collapsedVisibilityOwner: BrowserSidebarFolderVisibility {
            sidebarInteraction.collapsedFolderVisibility(
                for: BrowserFolderRuntimeAssignment(
                    folderID: folder.id, spaceID: context.space.id, profileID: context.space.profileID))
        }
    #else
        @State private var collapsedTabVisibility = BrowserCollapsedFolderTabVisibilityState()
    #endif
    @FocusState private var isTitleFocused: Bool

    private var configuration: BrowserFolderGroupConfiguration {
        BrowserFolderGroupConfiguration(
            sidebarInteraction: sidebarInteraction, folder: folder, depth: depth, context: context,
            spacePresentation: spacePresentation, inheritedKeptTabID: inheritedKeptTabID)
    }

    private var isExpanded: Binding<Bool> {
        Binding {
            !folder.isCollapsed
        } set: { isExpanded in
            guard configuration.isCurrentAndUnlocked else { return }
            context.browser.setFolderCollapsed(
                folder.id, matching: configuration.assignment, isCollapsed: !isExpanded)
        }
    }

    private var editingFolderRequest: Binding<BrowserFolderRuntimeAssignment?> {
        Binding {
            sidebarInteraction.editingFolderRequest
        } set: {
            sidebarInteraction.editingFolderRequest = $0
        }
    }

    private var interaction: BrowserFolderGroupInteractionContext {
        BrowserFolderGroupInteractionContext(
            isExpanded: isExpanded,
            editingFolderRequest: editingFolderRequest,
            draftTitle: $draftTitle,
            isChoosingColor: colorPresentation,
            isChoosingIcon: iconPresentation,
            folderSymbol: folderSymbolBinding,
            isConfirmingDeletion: deletionPresentation,
            collapsedTabVisibility: Binding(
                get: { collapsedTabVisibility }, set: { collapsedTabVisibility = $0 }),
            isTitleFocused: $isTitleFocused,
            folderColor: folderColorBinding,
            beginCreatingChild: beginCreatingChild,
            beginRenaming: beginRenaming,
            toggleExpansion: toggleExpansion,
            beginTitleEditingIfNeeded: beginTitleEditingIfNeeded,
            commitTitle: commitTitle,
            cancelTitleEditing: cancelTitleEditing,
            deleteFolder: deleteFolder,
            unloadKeptCollapsedTab: unloadKeptCollapsedTab
        )
    }

    var body: some View {
        let configuration = self.configuration
        let interaction = self.interaction
        let showsContents = configuration.showsContents
        VStack(spacing: 0) {
            BrowserFolderGroupSurface(configuration: configuration, interaction: interaction)
            if showsContents {
                folderContents(configuration: configuration)
            }
        }
        .environment(\.browserInteractionCapabilities, context.capabilities)
        .modifier(
            BrowserFolderSectionSurface(
                color: folder.displayColor,
                intensity: configuration.displayBranding?.folderColorIntensity ?? 0,
                textColorMode: configuration.displayBranding?.shownTextColorMode ?? .automatic,
                depth: depth,
                isSelected: BrowserSidebarSelection.showsSelected(.folder(folder.id), in: context),
                folderID: folder.id, reorder: sidebarInteraction.sidebarReorderState)
        )
        .modifier(BrowserFolderReorderContainer(configuration: configuration))
        .browserSidebarReorderZone(
            .section(.tabs(placement: folder.location, folderID: folder.id)),
            state: sidebarInteraction.sidebarReorderState
        )
        .browserSidebarReorderZone(
            .folder(folder.id),
            state: sidebarInteraction.sidebarReorderState,
            isActive: !showsContents
        )
        .modifier(
            BrowserFolderReorderReservation(configuration: configuration)
        )
        .onChange(of: configuration.folderRuntimeAssignment) { _, _ in
            clearUnavailableDeferredActions()
        }
        .modifier(
            SidebarSpaceRoleCleanupModifier(
                isAvailable: configuration.isAvailableForDisplay,
                hasPendingActions: sidebarInteraction.editingFolderRequest == configuration.folderRuntimeAssignment
                    || colorRequest != nil || iconRequest != nil || deletionRequest != nil,
                cancel: clearUnavailableDeferredActions
            )
        )
        .padding(.vertical, BrowserSidebarMetrics.containerSpacing)
    }

    /// Nested folders are children of the section they move with, so a parent's
    /// measurement, hover surface and lift include the entire expanded subtree.
    private func folderContents(configuration: BrowserFolderGroupConfiguration) -> some View {
        BrowserSidebarListRows(list: configuration.inside, context: context) { items in
            if items.isEmpty { BrowserFolderEmptyRunBand(configuration: configuration) }
        }
        .equatable()
        .browserSidebarReorderSectionIndicator(
            .tabs(placement: folder.location, folderID: folder.id),
            state: sidebarInteraction.sidebarReorderState
        )
        // Each row says its own depth; this is for what the run draws between
        // them, such as the slot a lift leaves.
        .environment(\.sidebarLayerDepth, depth + 1)
    }

    private func beginCreatingChild() {
        guard configuration.isCurrentAndUnlocked else { return }
        guard
            let childID = context.browser.addFolder(
                parentID: folder.id,
                matching: configuration.assignment
            )
        else {
            return
        }
        if inheritedKeptTabID != nil { expandFoldersAround() }
        isExpanded.wrappedValue = true
        sidebarInteraction.editingFolderRequest = BrowserFolderRuntimeAssignment(
            folderID: childID,
            spaceID: configuration.spaceID,
            profileID: configuration.profileID
        )
    }

    /// Opens every collapsed folder that holds this one. A folder drawn on a
    /// collapsed folder's way to its kept tab shows only that way, so a child
    /// made here would stay hidden, and its title could never start editing,
    /// until the folders around it open.
    private func expandFoldersAround() {
        var parentID = folder.parentID
        var visited: Set<UUID> = []
        while let id = parentID, visited.insert(id).inserted, let parent = context.space.folders.model(id) {
            if parent.isCollapsed {
                context.browser.setFolderCollapsed(id, matching: configuration.assignment, isCollapsed: false)
            }
            parentID = parent.parentID
        }
    }

    private func unloadKeptCollapsedTab(_ tabID: UUID) {
        guard configuration.isCurrentAndUnlocked else { return }
        collapsedTabVisibility.tabDidUnload(tabID)
        context.unload(tabID)
    }

    private func beginRenaming() {
        guard configuration.isCurrentAndUnlocked else { return }
        sidebarInteraction.editingFolderRequest = configuration.folderRuntimeAssignment
    }

    private func toggleExpansion() {
        guard !sidebarInteraction.sidebarReorderState.suppressesActivation,
            sidebarInteraction.editingFolderRequest != configuration.folderRuntimeAssignment,
            configuration.isCurrentAndUnlocked
        else {
            return
        }
        withAnimation(
            CrestMotion.disclosure.unlessReducingMotion(reduceMotion)
        ) {
            let nextExpansion = folder.isCollapsed
            collapsedTabVisibility.expansionDidChange(
                isExpanded: nextExpansion,
                selectedTabID: configuration.shownFolderTabID,
                folderTabIDs: configuration.folderTabIDs
            )
            isExpanded.wrappedValue = nextExpansion
        }
    }

    private func beginTitleEditingIfNeeded() {
        guard sidebarInteraction.editingFolderRequest == configuration.folderRuntimeAssignment,
            isDeferredAssignmentAvailable(
                configuration.folderRuntimeAssignment
            )
        else {
            isTitleFocused = false
            return
        }
        draftTitle = folder.title
        Task { @MainActor in
            isTitleFocused = true
        }
    }

    private func commitTitle() {
        guard let request = sidebarInteraction.editingFolderRequest,
            request == configuration.folderRuntimeAssignment
        else { return }
        sidebarInteraction.editingFolderRequest = nil
        guard isDeferredAssignmentAvailable(request) else { return }
        context.browser.renameFolder(
            request.folderID,
            matching: request.spaceAssignment,
            title: draftTitle
        )
    }

    private func cancelTitleEditing() {
        guard sidebarInteraction.editingFolderRequest == configuration.folderRuntimeAssignment else {
            return
        }
        draftTitle = folder.title
        sidebarInteraction.editingFolderRequest = nil
    }

    private func deleteFolder() {
        guard let request = deletionRequest else { return }
        deletionRequest = nil
        guard isDeferredAssignmentAvailable(request) else { return }
        context.browser.deleteFolder(request.folderID, matching: request.spaceAssignment)
    }

    private var folderColorBinding: Binding<BrandColor> {
        Binding(
            get: { folder.displayColor },
            set: { color in
                guard let request = colorRequest,
                    isDeferredAssignmentAvailable(request)
                else { return }
                context.browser.setFolderColor(
                    request.folderID,
                    matching: request.spaceAssignment,
                    color: color
                )
            }
        )
    }

    private var colorPresentation: Binding<Bool> {
        Binding {
            guard let request = colorRequest else { return false }
            return isDeferredAssignmentAvailable(request)
        } set: { isPresented in
            if isPresented, configuration.isCurrentAndUnlocked {
                colorRequest = configuration.folderRuntimeAssignment
            } else if !isPresented {
                colorRequest = nil
            }
        }
    }

    private var folderSymbolBinding: Binding<String> {
        Binding(
            get: { folder.displaySymbol },
            set: { symbol in
                guard let request = iconRequest,
                    isDeferredAssignmentAvailable(request)
                else { return }
                context.browser.setFolderSymbol(
                    request.folderID,
                    matching: request.spaceAssignment,
                    symbol: symbol
                )
            }
        )
    }

    private var iconPresentation: Binding<Bool> {
        Binding {
            guard let request = iconRequest else { return false }
            return isDeferredAssignmentAvailable(request)
        } set: { isPresented in
            if isPresented, configuration.isCurrentAndUnlocked {
                iconRequest = configuration.folderRuntimeAssignment
            } else if !isPresented {
                iconRequest = nil
            }
        }
    }

    private var deletionPresentation: Binding<Bool> {
        Binding {
            guard let request = deletionRequest else { return false }
            return isDeferredAssignmentAvailable(request)
        } set: { isPresented in
            if isPresented, configuration.isCurrentAndUnlocked {
                deletionRequest = configuration.folderRuntimeAssignment
            } else if !isPresented {
                deletionRequest = nil
            }
        }
    }

    private func isDeferredAssignmentAvailable(
        _ request: BrowserFolderRuntimeAssignment
    ) -> Bool {
        request == configuration.folderRuntimeAssignment && configuration.isCurrentAndUnlocked
    }

    private func clearUnavailableDeferredActions() {
        if let request = sidebarInteraction.editingFolderRequest,
            request == configuration.folderRuntimeAssignment,
            !isDeferredAssignmentAvailable(request)
        {
            sidebarInteraction.editingFolderRequest = nil
            isTitleFocused = false
        }
        if let request = iconRequest,
            !isDeferredAssignmentAvailable(request)
        {
            iconRequest = nil
        }
        if let request = colorRequest,
            !isDeferredAssignmentAvailable(request)
        {
            colorRequest = nil
        }
        if let request = deletionRequest,
            !isDeferredAssignmentAvailable(request)
        {
            deletionRequest = nil
        }
    }
}

extension BrowserFolderGroup: @MainActor Equatable {
    /// Groups are equal when they stand for the same folder in the same place,
    /// as SwiftUI compares a view's inputs: a list that redraws leaves them be.
    static func == (lhs: BrowserFolderGroup, rhs: BrowserFolderGroup) -> Bool {
        lhs.folder === rhs.folder && lhs.depth == rhs.depth && lhs.context == rhs.context
            && lhs.inheritedKeptTabID == rhs.inheritedKeptTabID
    }
}

/// The full folder keeps its registration for an owned lift, while ordinary
/// input follows the page role entirely within this interaction leaf.
private struct BrowserFolderReorderContainer: ViewModifier {
    @Environment(BrowserSidebarInteractionState.self) private var sidebarInteraction

    let configuration: BrowserFolderGroupConfiguration

    @Environment(\.sidebarSpaceIsSelected) private var isSelected

    func body(content: Content) -> some View {
        content.browserSidebarReorderContainer(
            item: .folder(configuration.dragItem),
            section: configuration.folder.reorderSection,
            reorder: BrowserSidebarReorderContext(
                browser: configuration.browser, spaceAccess: configuration.spaceAccess,
                state: sidebarInteraction.sidebarReorderState),
            isEnabled: (SidebarSpaceRole.permitsInteraction(
                isSelected: isSelected, isAvailable: configuration.isAvailableForDisplay) || isLiftedFolder)
                && configuration.capabilities.supportsOrganization
        )
    }

    private var isLiftedFolder: Bool {
        guard let lift = sidebarInteraction.sidebarReorderState.lift,
            case .folder(let item) = lift.item
        else { return false }
        return item.folderID == configuration.folder.id
            && item.spaceID == configuration.spaceID && item.profileID == configuration.profileID
    }
}

/// The landing slot a folder's tab run keeps open at its end.
///
/// A finger cannot aim at the seam between two rows that touch, so a shell
/// that reserves those places gets a zone of its own here. Where the seam is
/// aimable the reservation would only add an empty band nothing lands in.
private struct BrowserFolderReorderReservation: ViewModifier {
    @Environment(BrowserSidebarInteractionState.self) private var sidebarInteraction

    let configuration: BrowserFolderGroupConfiguration

    @ViewBuilder
    func body(content: Content) -> some View {
        if configuration.capabilities.reservesReorderSectionZones {
            content.browserSidebarReorderSectionReservation(
                .tabs(placement: configuration.folder.location, folderID: configuration.folder.id),
                state: sidebarInteraction.sidebarReorderState
            )
        } else {
            content
        }
    }
}
