import UIKit

/// Hands a file to the share sheet or the Files picker, on a device without a
/// Finder. A file staged in `temporaryDirectoryURL` for the export is removed
/// once the person is done with it.
struct MobileBrowserFilePresenter: BrowserFileDestinationOpener {
    // MARK: - Variables

    let temporaryDirectoryURL: URL?

    // MARK: - Actions - Presenting

    /// A device without a Finder exports instead of opening.
    func openFile(_ fileURL: URL) {}

    /// A device without a Finder exports instead of revealing.
    func revealFile(_ fileURL: URL) {}

    func shareFile(_ fileURL: URL) {
        let controller = MobileBrowserExportActivityController(
            fileURL: fileURL,
            temporaryDirectoryURL: temporaryDirectoryURL
        )
        MobileBrowserDialogPresenter.present(controller) {
            controller.cleanupTemporaryFiles()
        }
    }

    func saveFileToFiles(_ fileURL: URL) {
        if let temporaryDirectoryURL {
            let controller = MobileBrowserExportPickerController(
                fileURL: fileURL,
                temporaryDirectoryURL: temporaryDirectoryURL
            )
            MobileBrowserDialogPresenter.present(controller) {
                controller.cleanupTemporaryFiles()
            }
            return
        }
        let controller = UIDocumentPickerViewController(
            forExporting: [fileURL],
            asCopy: true
        )
        controller.shouldShowFileExtensions = true
        MobileBrowserDialogPresenter.present(controller, fallback: {})
    }
}
