import SwiftUI

/// The one place a settings destination becomes a pane.
///
/// Both shells navigate the same ``BrowserSettingsDestination`` catalog to the
/// same panes. What differs is the chrome around a pane and which destinations a
/// shell offers at all — neither is a reason for a second switch, so the shells
/// hand this router their inputs and decorate its output: the desktop wraps it
/// in a `BrowserSettingsPage`, touch shows it as it comes.
///
struct BrowserSettingsDestinationRouter: View {
    let destination: BrowserSettingsDestination
    let browser: BrowserStore
    let dataDeleter: any BrowserSpaceDataDeleting
    let cloudSync: BrowserCloudSyncController
    let downloadCenter: BrowserDownloadCenter
    let permissionCenter: BrowserSitePermissionCenter
    let contentBlockingErrorDescription: String?
    /// What this shell can offer a reader who wants to set Crest up again.
    let importActions: [BrowserAdvancedImportAction]
    var showsMacOSImportRequirement = false
    var requestedSpaceID: UUID? = nil
    var requestRevision = 0
    var featureFlagsSpace: SpaceModel? = nil
    /// Opens Feature Flags from Advanced, for a shell that lists it there.
    var openFeatureFlags: (() -> Void)? = nil

    @ViewBuilder
    var body: some View {
        switch destination.kind {
        case .general:
            BrowserGeneralSettingsPane(browser: browser)
        case .engines:
            #if os(macOS)
                BrowserEngineSettingsPane(core: browser.core)
            #endif
        case .spaces:
            BrowserPlatformSpaceSettingsPane(
                browser: browser,
                dataDeleter: dataDeleter,
                requestedSpaceID: requestedSpaceID,
                requestRevision: requestRevision
            )
        case .sync:
            BrowserSyncSettingsView(browser: browser, cloudSync: cloudSync)
        case .privacy:
            #if os(macOS)
                // Each Space's own privacy is a page of that Space.
                BrowserSystemPrivacySettingsPane(browser: browser)
            #else
                BrowserPrivacySettingsPane(
                    browser: browser,
                    downloadCenter: downloadCenter,
                    permissionCenter: permissionCenter,
                    contentBlockingErrorDescription:
                        contentBlockingErrorDescription
                )
            #endif
        case .extensions:
            BrowserEngineExtensionSettingsPane(browser: browser)
        case .featureFlags:
            BrowserEngineRegistration.featureFlagsPane(space: featureFlagsSpace, browser: browser)
        case .advanced:
            BrowserAdvancedSettingsPane(
                browser: browser,
                importActions: importActions,
                showsMacOSImportRequirement: showsMacOSImportRequirement,
                openFeatureFlags: openFeatureFlags
            )
        case .about:
            BrowserAboutSettingsPane()
        case .agents:
            #if os(macOS)
                BrowserAgentsSettingsPane(core: browser.core)
            #endif
        }
    }
}
