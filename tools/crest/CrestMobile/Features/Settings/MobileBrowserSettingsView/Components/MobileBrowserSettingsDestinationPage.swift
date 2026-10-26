import SwiftUI

struct MobileBrowserSettingsDestinationPage: View {
    let destination: BrowserSettingsDestination
    let browser: BrowserStore
    let pages: MobileBrowserPageStore
    let dataDeleter: any BrowserSpaceDataDeleting

    @Environment(BrowserCloudSyncController.self) private var cloudSync

    var body: some View {
        BrowserSettingsDestinationRouter(
            destination: destination,
            browser: browser,
            dataDeleter: dataDeleter,
            cloudSync: cloudSync,
            downloadCenter: pages.downloadCenter,
            permissionCenter: pages.permissionCenter,
            contentBlockingErrorDescription:
                pages.contentBlockingErrorDescription,
            importActions: [],
            showsMacOSImportRequirement: true,
        )

    }

}
