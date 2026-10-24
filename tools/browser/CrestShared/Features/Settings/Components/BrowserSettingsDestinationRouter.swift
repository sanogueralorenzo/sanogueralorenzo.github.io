import SwiftUI

/// The one place a settings destination becomes a pane.
///
/// Both shells navigate the same ``BrowserSettingsDestination`` catalog to the
/// same panes. What differs is the chrome around a pane and which destinations a
/// shell offers at all — neither is a reason for a second switch, so the shells
/// hand this router their inputs and decorate its output: the desktop wraps it
/// in a `BrowserSettingsPage`, touch shows it as it comes.
///
/// A destination a shell cannot host arrives here as absent data rather than as
/// a missing case. No shortcut store means no Shortcuts pane — the same answer
/// `BrowserPlatformSettingsDestinationCatalog` already gives the shells' lists.
struct BrowserSettingsDestinationRouter: View {
    let destination: BrowserSettingsDestination
    let browser: BrowserStore
    let spaceAccess: BrowserSpaceAccessController
    let dataDeleter: any BrowserSpaceDataDeleting
    let cloudSync: BrowserCloudSyncController
    let downloadCenter: BrowserDownloadCenter
    let permissionCenter: BrowserSitePermissionCenter
    let contentBlockingErrorDescription: String?
    /// What this shell can offer a reader who wants to set Crest up again.
    let setupActions: [BrowserAdvancedSetupAction]
    /// How much of the passwords pane this shell puts on the page.
    let passwordLayout: BrowserPasswordSettingsLayout
    var showsMacOSImportRequirement = false
    /// The Settings window's own search field, for a shell that has one.
    var passwordSearchText: Binding<String> = .constant("")
    /// What a shell that keeps the password manager elsewhere does when the pane
    /// is asked for it.
    var managePasswords: (() -> Void)? = nil
    /// Absent where the shell has no rebindable command table.
    var shortcuts: BrowserShortcutStore? = nil
    var requestedSpaceID: UUID? = nil
    var requestRevision = 0
    /// The Space whose engine pages the feature flags pane shows, or nil
    /// while it is locked.
    var featureFlagsSpace: SpaceModel? = nil
    /// Opens Feature Flags from Advanced, for a shell that lists it there.
    var openFeatureFlags: (() -> Void)? = nil

    @ViewBuilder
    var body: some View {
        switch destination.kind {
        case .general:
            BrowserGeneralSettingsPane(browser: browser, spaceAccess: spaceAccess)
        case .tabs:
            BrowserTabsSettingsPane(browser: browser)
        case .search:
            BrowserSearchSettingsPane(browser: browser)
        case .engines:
            #if os(macOS)
                BrowserEngineSettingsPane(core: browser.core)
            #endif
        case .lookAndFeel:
            BrowserLookAndFeelSettingsPane(space: browser.shownSpace.map(BrowserSpaceAppearance.init(space:)))
        case .links:
            BrowserLinkSettingsPane(
                browser: browser,
                spaceAccess: spaceAccess
            )
        case .shortcuts:
            shortcuts.map { shortcuts in
                BrowserPlatformShortcutSettingsPane(
                    shortcuts: shortcuts,
                    requestedSpaceID: requestedSpaceID,
                    requestRevision: requestRevision
                )
            }
        case .spaces:
            BrowserPlatformSpaceSettingsPane(
                browser: browser,
                spaceAccess: spaceAccess,
                dataDeleter: dataDeleter,
                requestedSpaceID: requestedSpaceID,
                requestRevision: requestRevision
            )
        case .sync:
            BrowserSyncSettingsView(browser: browser, cloudSync: cloudSync)
        case .privacy:
            #if os(macOS)
                // Each Space's own privacy is a page of that Space.
                BrowserSystemPrivacySettingsPane(browser: browser, spaceAccess: spaceAccess)
            #else
                BrowserPrivacySettingsPane(
                    browser: browser,
                    downloadCenter: downloadCenter,
                    spaceAccess: spaceAccess,
                    permissionCenter: permissionCenter,
                    contentBlockingErrorDescription:
                        contentBlockingErrorDescription
                )
            #endif
        case .extensions:
            BrowserEngineExtensionSettingsPane(browser: browser, spaceAccess: spaceAccess)
        case .passwords:
            BrowserPasswordSettingsPane(
                browser: browser,
                spaceAccess: spaceAccess,
                layout: passwordLayout,
                searchText: passwordSearchText,
                manage: managePasswords
            )
        case .featureFlags:
            BrowserEngineRegistration.featureFlagsPane(space: featureFlagsSpace, browser: browser)
        case .advanced:
            BrowserAdvancedSettingsPane(
                browser: browser,
                spaceAccess: spaceAccess,
                setupActions: setupActions,
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
