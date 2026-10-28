import SwiftUI

/// The windowed shell's sidebar adapter: it resolves what this shell can do,
/// binds the sidebar's ports to the window's card pool, and answers the chrome's
/// presentation with the settings scene.
struct BrowserRootSidebarContent: View {
    let model: BrowserRootModel
    let spaceSettingsPresentation: BrowserSpaceSettingsPresentationState
    let commandSurfaceNamespace: Namespace.ID
    let tabPromotionNamespace: Namespace.ID

    var body: some View {
        BrowserSidebar(
            browser: model.browser,
            pageAccess: pageAccess,
            capabilities: capabilities,
            utilityCoordinator: utilityCoordinator,
            utilityPresentation: model.chrome.utilityPresentation,
            chromeActions: chromeActions
        ) { context in
            BrowserSidebarLoadedContent(
                context: context,
                pages: model.pages,
                activateAddress: { model.chrome.openLocation(model.address) },
                openNewTab: model.openNewTab,
                commandSurfaceNamespace: commandSurfaceNamespace,
                tabPromotionNamespace: tabPromotionNamespace
            )
        }
    }

    /// What this shell can do: a pointer rests over the chrome, nothing is aimed
    /// at with a finger, and the window never zooms a page in.
    private var capabilities: BrowserInteractionCapabilities {
        BrowserInteractionCapabilities()
    }

    private var pageAccess: BrowserSidebarPageAccess {
        BrowserSidebarPageAccess(pages: model.pages, browser: model.browser)
    }

    private var utilityCoordinator: BrowserSidebarUtilityCoordinator {
        BrowserSidebarUtilityCoordinator(
            browser: model.browser,
            pages: model.pages
        )
    }

    private var chromeActions: BrowserSidebarChromeActions {
        let create: (() -> Void)? = model.browser.isTemporaryWorkspace ? nil : { createSpace() }
        return BrowserSidebarChromeActions(
            presentSpaceSettings: { presentSpaceSettings(for: $0) },
            presentHistory: { model.chrome.presentUtility(.history) },
            presentArchive: { model.chrome.presentUtility(.archive) },
            presentDownloads: { model.chrome.presentUtility(.downloads) },
            createSpace: create,
            deleteSpace: model.browser.isTemporaryWorkspace ? nil : { deleteSpace($0) }
        )
    }

    private func presentSpaceSettings(
        for assignment: BrowserSpaceRuntimeAssignment,
        intent: BrowserSettingsSpaceIntent = .none
    ) {
        guard model.browser.spaceModel(matching: assignment) != nil else { return }
        spaceSettingsPresentation.present(
            BrowserSettingsSpaceRequest(tab: .identity, intent: intent), assignment: assignment)
        model.browser.selectSpace(assignment.spaceID)
        model.browser.openSettings()
        model.pages.select()
    }

    private func createSpace() {
        model.browser.addSpace()
        guard let space = model.browser.shownSpace else { return }
        model.pages.select()
        presentSpaceSettings(for: BrowserSpaceRuntimeAssignment(space: space), intent: .newSpace)
    }

    private func deleteSpace(_ assignment: BrowserSpaceRuntimeAssignment) {
        Task { @MainActor in
            guard let space = model.browser.spaceModel(matching: assignment) else { return }
            do {
                try await model.browser.deleteSpace(
                    space.id, dataDeleter: model.browser.family.spaceDataDeleter ?? model.pages)
            } catch {
                model.chrome.showNotice(
                    BrowserNotice(
                        message: error.localizedDescription, systemImage: "exclamationmark.triangle"))
            }
        }
    }

}
