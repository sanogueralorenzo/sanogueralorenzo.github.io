import Dispatch
import Observation
import UIKit
import UniformTypeIdentifiers
import WebKit

@MainActor
final class MobileBrowserExportPickerController: UIDocumentPickerViewController,
    UIDocumentPickerDelegate
{
    private let temporaryDirectoryURL: URL
    private var hasCleanedUp = false

    init(fileURL: URL, temporaryDirectoryURL: URL) {
        self.temporaryDirectoryURL = temporaryDirectoryURL
        super.init(forExporting: [fileURL], asCopy: true)
        shouldShowFileExtensions = true
        delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        guard !hasCleanedUp else { return }
        try? FileManager.default.removeItem(at: temporaryDirectoryURL)
    }

    func documentPicker(
        _ controller: UIDocumentPickerViewController,
        didPickDocumentsAt urls: [URL]
    ) {
        cleanupTemporaryFiles()
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        cleanupTemporaryFiles()
    }

    func cleanupTemporaryFiles() {
        guard !hasCleanedUp else { return }
        hasCleanedUp = true
        let directoryURL = temporaryDirectoryURL
        Task.detached(priority: .utility) {
            try? FileManager.default.removeItem(at: directoryURL)
        }
    }
}
