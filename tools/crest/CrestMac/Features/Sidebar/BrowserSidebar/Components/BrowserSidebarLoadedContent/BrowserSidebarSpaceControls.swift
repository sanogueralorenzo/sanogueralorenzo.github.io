import SwiftUI

/// Space selection shares the titlebar; navigation has its own row below it.
struct BrowserSidebarSpaceControls: View {
    // MARK: - Variables

    let context: BrowserSidebarContext
    let space: SpaceModel
    let pages: BrowserPagePool
    let activateAddress: () -> Void
    let openNewTab: () -> Void

    @State private var isWebsiteSettingsPresented = false

    private var assignment: BrowserSpaceRuntimeAssignment { BrowserSpaceRuntimeAssignment(space: space) }

    private var actions: BrowserSpaceHeaderActions {
        BrowserSpaceHeaderActions(
            openNewTab: openNewTab,
            createFolder: createFolder,
            createGitHubFolder: {
                context.utilityPresentation.dismiss()
                BrowserGitHubFolderAction(browser: context.browser, assignment: assignment).create()
            },
            showHistory: context.chromeActions.presentHistory,
            showArchive: context.chromeActions.presentArchive,
            showDownloads: context.chromeActions.presentDownloads,
            showTabs: context.utilityPresentation.surface == nil ? nil : { context.utilityPresentation.dismiss() },
            showWebsiteSettings: siteControl == nil
                ? nil
                : {
                    isWebsiteSettingsPresented = true
                    context.utilityPresentation.setSiteControlPresented(true)
                },
            showSettings: {
                context.browser.openSettings()
                pages.select()
            },
            settingsShortcut: BrowserMacApplicationAction.settings.keyEquivalent.first.map {
                BrowserShortcut(key: .character($0), modifiers: .command)
            }
        )
    }

    // MARK: - Actions - Drawing

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer(minLength: 70)
                BrowserSpaceSwitcher(
                    browser: context.browser,
                    capabilities: context.capabilities,
                    selectSpace: context.selectSpace,
                    commands: spaceCommands
                )
                .frame(minWidth: 56, maxWidth: 100)
            }
            .padding(.horizontal, BrowserSidebarMetrics.layerInset)
            .frame(height: BrowserChromeLayout.sidebarTitlebarHeight)

            navigation
        }
        .padding(.bottom, CrestSpacing.extraSmall)
    }

    private var navigation: some View {
        BrowserSidebarNavigationControls(
            port: BrowserSidebarNavigationPort(
                pages: pages, browser: context.browser, showHistory: context.chromeActions.presentHistory),
            capabilities: context.capabilities,
            trailingAccessory: {
                BrowserSidebarSearchButton(activate: activateAddress)
                if let siteControl {
                    BrowserSiteControlHost(configuration: siteControl, isPresented: $isWebsiteSettingsPresented) {
                        actionsMenu
                    }
                } else {
                    actionsMenu
                }
            }
        )
    }

    private var actionsMenu: some View {
        BrowserSpaceHeaderActionsMenu(
            isPrivateBrowsing: context.browser.isPrivateBrowsing,
            metrics: context.capabilities.spaceHeaderMetrics,
            actions: actions
        )
        .onGeometryChange(for: CGRect.self) {
            $0.frame(in: .global)
        } action: {
            context.utilityPresentation.recordTriggerFrame($0)
        }
    }

    private var siteControl: BrowserSiteControlConfiguration? {
        guard !context.browser.isDeleting(space.id),
            let tabID = context.browser.selectedTabID(in: space.id),
            let page = pages.activePage(
                matching: BrowserTabRuntimeAssignment(tabID: tabID, spaceID: space.id, profileID: space.profileID)),
            page.live.displayURL != nil
        else { return nil }
        return BrowserSiteControlConfiguration(
            page: page, space: space, selectedTabID: tabID,
            permissionCenter: pages.permissionCenter,
            presentationChanged: { context.utilityPresentation.setSiteControlPresented($0) },
            contextMenuPresentationChanged: { context.utilityPresentation.setSiteControlContextMenuPresented($0) }
        )
    }

    // MARK: - Actions - Spaces

    private func spaceCommands(_ space: BrowserSpaceIdentity) -> [CrestSpaceChipCommand] {
        var commands: [CrestSpaceChipCommand] = []
        if let create = context.chromeActions.createSpace {
            commands.append(
                CrestSpaceChipCommand(id: "newSpace", title: "New Space", systemImage: "plus", perform: create))
        }
        commands.append(
            CrestSpaceChipCommand(
                id: "editSpace", title: "Edit Space", systemImage: "pencil",
                perform: { context.chromeActions.presentSpaceSettings(space.assignment) }))
        if let delete = context.chromeActions.deleteSpace {
            commands.append(
                CrestSpaceChipCommand(
                    id: "deleteSpace", title: "Delete Space", systemImage: "trash", isDestructive: true,
                    isEnabled: context.browser.availableSpaces.count > 1 && !context.browser.isDeleting(space.id),
                    perform: { delete(space.assignment) }))
        }
        return commands
    }

    private func createFolder() {
        guard context.browser.selectedAvailableSpace(matching: assignment) != nil,
            let folderID = context.browser.addFolder(matching: assignment)
        else { return }
        context.utilityPresentation.dismiss()
        context.sidebarInteraction.editingFolderRequest = BrowserFolderRuntimeAssignment(
            folderID: folderID, spaceID: assignment.spaceID, profileID: assignment.profileID)
    }

}
