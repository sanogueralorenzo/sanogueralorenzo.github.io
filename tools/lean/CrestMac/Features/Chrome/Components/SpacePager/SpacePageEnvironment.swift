import SwiftUI

// MARK: - Types

/// The objects a window shares with the views in it, as one Space page root
/// carries them into the page's own hosting view.
struct SpacePageObjects {
    let sidebarInteraction: BrowserSidebarInteractionState?
    let extensionSidePanel: BrowserExtensionSidePanelHost?
    let downloadFeedback: BrowserMacDownloadFeedbackState?
    let passkeyAccess: BrowserPasskeyAccessController?
    let softwareUpdates: BrowserSoftwareUpdateService?
    let agentEndpoint: BrowserAgentEndpointStatus?
    let core: CrestCore?
}

/// Reads the objects a window shares with its views where a Space pager sits,
/// so the pager can hand them to each page it hosts.
///
/// A page lives in a hosting view of its own and otherwise inherits these
/// through the native view hierarchy. A pager builds pages outside SwiftUI's
/// updates too, during a slide, and a page whose view required one of them
/// before it had inherited them would stop Crest, so every page carries its
/// own.
struct SpacePageEnvironment: DynamicProperty {
    // MARK: - Variables

    @Environment(BrowserSidebarInteractionState.self) private var sidebarInteraction: BrowserSidebarInteractionState?
    @Environment(BrowserExtensionSidePanelHost.self) private var extensionSidePanel: BrowserExtensionSidePanelHost?
    @Environment(BrowserMacDownloadFeedbackState.self) private var downloadFeedback: BrowserMacDownloadFeedbackState?
    @Environment(BrowserPasskeyAccessController.self) private var passkeyAccess: BrowserPasskeyAccessController?
    @Environment(BrowserSoftwareUpdateService.self) private var softwareUpdates: BrowserSoftwareUpdateService?
    @Environment(BrowserAgentEndpointStatus.self) private var agentEndpoint: BrowserAgentEndpointStatus?
    @Environment(CrestCore.self) private var core: CrestCore?

    /// The objects as they are now. Read it while the pager updates; pages it
    /// builds later keep this value.
    var objects: SpacePageObjects {
        SpacePageObjects(
            sidebarInteraction: sidebarInteraction, extensionSidePanel: extensionSidePanel,
            downloadFeedback: downloadFeedback, passkeyAccess: passkeyAccess, softwareUpdates: softwareUpdates,
            agentEndpoint: agentEndpoint, core: core)
    }
}
