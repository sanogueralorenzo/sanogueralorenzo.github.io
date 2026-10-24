import SwiftUI

struct BrowserTabBatchMenu: View {
    @Environment(BrowserSidebarInteractionState.self) private var sidebarInteraction

    let request: BrowserCapturedSelection
    let browser: BrowserStore
    let spaceAccess: BrowserSpaceAccessController
    var unload: ((UUID) -> Void)? = nil

    private var actions: BrowserTabBatchActions { BrowserTabBatchActions(browser: browser, spaceAccess: spaceAccess) }
    private var count: Int { request.ids.count }

    var body: some View {
        if request.hasFolders { folderMenu } else { tabMenu }
    }

    @ViewBuilder
    private var tabMenu: some View {
        Group {
            if count == 1 { Text("1 tab selected") } else { Text("\(count) tabs selected") }
        }
        .disabled(true)
        Divider()
        Button("Copy Link URLs", systemImage: "link", action: copyLinks)
        Divider()
        // A selection of pinned tabs only is unpinned, the pair of Pin N Tabs;
        // any other selection may hold tabs to pin.
        if request.members.allSatisfy({ $0.placement == .pinned }) {
            action(
                count == 1 ? "Unpin Tab" : "Unpin \(count) Tabs", systemImage: "pin.slash",
                browser.filing(request, .current))
        } else {
            action(
                count == 1 ? "Pin Tab" : "Pin \(count) Tabs", systemImage: "pin", browser.filing(request, .pinned))
            action("Move to Current Tabs", systemImage: "rectangle.stack", browser.filing(request, .current))
        }
        Menu("Move to Folder", systemImage: "folder") {
            action("New Current Tabs Folder", browser.filingInNewFolder(request, in: .current))
            action("New Saved Folder", browser.filingInNewFolder(request, in: .saved))
            action("Saved Tabs", browser.filing(request, .saved))
            ForEach(folderChoices) { choice in
                action(named: choice.pathTitle, browser.filing(request, choice.folder.location, folder: choice.id))
            }
        }
        Menu("Move to Space", systemImage: "square.grid.2x2") {
            ForEach(
                browser.availableTabMoveDestinationSpaces(from: request.assignment, accessController: spaceAccess)
            ) { space in
                let moving = browser.moving(request, to: BrowserSpaceRuntimeAssignment(space: space))
                Button {
                    actions.perform(moving, for: request)
                } label: {
                    BrowserSpaceIdentityLabel(space: space)
                }
                .disabled(!actions.isAvailable(moving))
            }
        }
        action("Combine in Split View", systemImage: "rectangle.split.2x1", browser.splitting(request))
        if request.members.contains(where: { $0.splitGroupID != nil }) {
            action(
                "Separate Selected Splits", systemImage: "rectangle.split.2x1.slash", browser.separatingSplits(request))
        }
        Divider()
        action("Keep Pages Loaded", systemImage: "lock", browser.keepingLoaded(request, true))
        action("Stop Keeping Pages Loaded", systemImage: "lock.open", browser.keepingLoaded(request, false))
        action("Duplicate \(count) Tabs", systemImage: "plus.square.on.square", browser.duplicating(request))
        if let unload {
            let unloading = browser.keepingLoaded(request, false)
            Button("Unload \(count) Pages", systemImage: "minus") {
                if let reason = actions.reason(unloading) {
                    browser.tabMultiSelection.message = reason
                    return
                }
                for id in request.ids { unload(id) }
                browser.tabMultiSelection.clear()
            }
            .disabled(!actions.isAvailable(unloading))
        }
        action("Archive Selected Tabs", systemImage: "archivebox", browser.closing(request))
        action("Delete \(count) Tabs", systemImage: "trash", role: .destructive, browser.deleting(request))
        Divider()
        Button("Select All Tabs") {
            browser.tabMultiSelection.selectAll(
                units: BrowserSidebarSelection.itemUnits(in: browser))
        }
        Button("Deselect All") { browser.tabMultiSelection.clear() }
    }

    private var folderMenu: some View {
        Group {
            Group {
                if request.rootItems.count == 1 {
                    Text("1 item selected")
                } else {
                    Text("\(request.rootItems.count) items selected")
                }
            }
            .disabled(true)
            Divider()
            action("Move to Current Tabs", systemImage: "rectangle.stack", browser.filing(request, .current))
            action("Move to Saved Tabs", systemImage: "bookmark", browser.filing(request, .saved))
            Menu("Move to Folder", systemImage: "folder") {
                action("New Current Tabs Folder", browser.filingInNewFolder(request, in: .current))
                action("New Saved Folder", browser.filingInNewFolder(request, in: .saved))
                ForEach(folderChoices.filter { !request.folderIDs.contains($0.id) }) { choice in
                    action(named: choice.pathTitle, browser.filing(request, choice.folder.location, folder: choice.id))
                }
            }
            Divider()
            Button("Select All Items") {
                browser.tabMultiSelection.selectAll(
                    units: BrowserSidebarSelection.itemUnits(in: browser))
            }
            Button("Deselect All") { browser.tabMultiSelection.clear() }
        }
    }

    /// A menu item that performs `batch`, offered only when the core would take it.
    private func action(
        _ title: LocalizedStringKey, systemImage: String, role: ButtonRole? = nil, _ batch: BrowserTabBatch
    ) -> some View {
        Button(title, systemImage: systemImage, role: role) { actions.perform(batch, for: request) }
            .disabled(!actions.isAvailable(batch))
    }

    /// A menu item without a symbol that performs `batch`, offered only when
    /// the core would take it.
    private func action(_ title: LocalizedStringKey, _ batch: BrowserTabBatch) -> some View {
        Button(title) { actions.perform(batch, for: request) }
            .disabled(!actions.isAvailable(batch))
    }

    /// A menu item titled by a folder's own name.
    private func action(named title: String, _ batch: BrowserTabBatch) -> some View {
        Button(title) { actions.perform(batch, for: request) }
            .disabled(!actions.isAvailable(batch))
    }

    private func copyLinks() { actions.copyLinks(request) }

    /// Every folder of the selection's Space, saved first, in the order the
    /// sidebar lists them.
    private var folderChoices: [SpaceModel.FolderChoice] {
        browser.spaceModel(request.spaceID)?.folderChoices(in: [.saved, .current]) ?? []
    }
}
