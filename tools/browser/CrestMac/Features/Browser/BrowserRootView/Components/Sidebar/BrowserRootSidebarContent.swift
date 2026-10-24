import SwiftUI

/// The windowed shell's sidebar adapter: it resolves what this shell can do,
/// binds the sidebar's ports to the window's card pool, and answers the chrome's
/// presentation with the settings scene.
struct BrowserRootSidebarContent: View {
    let model: BrowserRootModel
    let spaceSettingsPresentation: BrowserSpaceSettingsPresentationState
    let commandSurfaceNamespace: Namespace.ID
    let tabPromotionNamespace: Namespace.ID

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        BrowserSidebar(
            browser: model.browser,
            pageAccess: pageAccess,
            spaceAccess: model.spaceAccess,
            capabilities: capabilities,
            utilityCoordinator: utilityCoordinator,
            utilityPresentation: model.chrome.utilityPresentation,
            chromeActions: chromeActions
        ) { context in
            BrowserSidebarLoadedContent(
                context: context,
                pages: model.pages,
                address: model.addressBinding,
                isAddressEditing: model.isAddressEditingBinding,
                addressFocusRequest: model.chrome.addressFocusRequest,
                activateAddress: { model.chrome.openLocation(model.address) },
                submitAddress: model.submitAddress,
                openNewTab: model.openNewTab,
                sidebarToggleAction:
                    model.sidebarPresentation.sidebarToggleAction,
                toggleSidebar: {
                    model.toggleSidebar(reduceMotion: reduceMotion)
                },
                commandSurfaceNamespace: commandSurfaceNamespace,
                commandPaletteHandoff: model.commandPaletteHandoff(reduceMotion: reduceMotion),
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
        BrowserSidebarPageAccess(pages: model.pages, browser: model.browser, spaceAccess: model.spaceAccess)
    }

    private var utilityCoordinator: BrowserSidebarUtilityCoordinator {
        BrowserSidebarUtilityCoordinator(
            browser: model.browser,
            pages: model.pages,
            spaceAccess: model.spaceAccess
        )
    }

    private var chromeActions: BrowserSidebarChromeActions {
        let create: (() -> Void)? = model.browser.isTemporaryWorkspace ? nil : { createSpace() }
        return BrowserSidebarChromeActions(
            presentSpaceSettings: { presentSpaceSettings(for: $0) },
            presentHistory: { model.chrome.presentUtility(.history) },
            createSpace: create
        )
    }

    private func presentSpaceSettings(
        for assignment: BrowserSpaceRuntimeAssignment,
        intent: BrowserSettingsSpaceIntent = .none
    ) {
        spaceSettingsPresentation.present(
            BrowserSettingsSpaceRequest(tab: .appearance, intent: intent), assignment: assignment)
        model.browser.openSettings()
        model.pages.select()
    }

    private func createSpace() {
        model.browser.addSpace()
        guard let space = model.browser.shownSpace else { return }
        model.pages.select()
        presentSpaceSettings(for: BrowserSpaceRuntimeAssignment(space: space), intent: .newSpace)
    }
}
