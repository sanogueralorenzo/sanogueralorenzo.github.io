import AppKit

/// Hands a finished download to Finder: the windowed shell opens the file or
/// shows it where it was saved.
struct BrowserWorkspaceFileOpener: BrowserFileDestinationOpener {
    // MARK: - Actions - Opening

    func openFile(_ fileURL: URL) {
        NSWorkspace.shared.open(fileURL)
    }

    func revealFile(_ fileURL: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([
            fileURL
        ])
    }

    /// The windowed shell does not offer this destination.
    func shareFile(_ fileURL: URL) {}

    /// The windowed shell does not offer this destination.
    func saveFileToFiles(_ fileURL: URL) {}
}
