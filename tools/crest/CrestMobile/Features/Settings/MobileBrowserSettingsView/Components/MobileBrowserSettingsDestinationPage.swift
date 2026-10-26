import SwiftUI

struct MobileBrowserSettingsDestinationPage: View {
    let destination: BrowserSettingsDestination
    let browser: BrowserStore
    let pages: MobileBrowserPageStore
    let spaceAccess: BrowserSpaceAccessController
    let dataDeleter: any BrowserSpaceDataDeleting

    @Environment(BrowserCloudSyncController.self) private var cloudSync
    @Environment(BrowserOnboardingCoordinator.self) private var onboardingCoordinator

    @State private var presentsPasswords = false

    var body: some View {
        BrowserSettingsDestinationRouter(
            destination: destination,
            browser: browser,
            spaceAccess: spaceAccess,
            dataDeleter: dataDeleter,
            cloudSync: cloudSync,
            downloadCenter: pages.downloadCenter,
            permissionCenter: pages.permissionCenter,
            contentBlockingErrorDescription:
                pages.contentBlockingErrorDescription,
            setupActions: setupActions,
            passwordLayout: .mobilePage,
            showsMacOSImportRequirement: true,
            managePasswords: { presentsPasswords = true }
        )
        .sheet(isPresented: $presentsPasswords) {
            MobilePasswordSettingsView(
                browser: browser,
                spaceAccess: spaceAccess
            )
        }
    }

    private var setupActions: [BrowserAdvancedSetupAction] {
        [
            .init(
                id: "rerun-onboarding",
                title: "Rerun onboarding",
                symbol: "arrow.counterclockwise",
                identifier: "mobile-open-setup",
                action: rerunOnboarding
            )
        ]
    }

    private func rerunOnboarding() {
        onboardingCoordinator.presentOnMobile(.rerun)
    }
}
