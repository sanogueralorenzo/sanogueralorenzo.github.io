import Dispatch
import Observation
import UIKit
import UniformTypeIdentifiers
import WebKit

@MainActor
final class MobileBrowserExportActivityController: UIActivityViewController {
    private let temporaryDirectoryURL: URL?
    private var hasCleanedUp = false

    init(fileURL: URL, temporaryDirectoryURL: URL?) {
        self.temporaryDirectoryURL = temporaryDirectoryURL
        super.init(activityItems: [fileURL], applicationActivities: nil)
        completionWithItemsHandler = { [weak self] _, _, _, _ in
            self?.cleanupTemporaryFiles()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        guard !hasCleanedUp, let temporaryDirectoryURL else { return }
        try? FileManager.default.removeItem(at: temporaryDirectoryURL)
    }

    func cleanupTemporaryFiles() {
        guard !hasCleanedUp, let temporaryDirectoryURL else { return }
        hasCleanedUp = true
        Task.detached(priority: .utility) {
            try? FileManager.default.removeItem(at: temporaryDirectoryURL)
        }
    }
}
