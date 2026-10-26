import Foundation

/// Hands a file to the part of the system a download destination names, the
/// way one shell does it: one method per destination. A shell that does not
/// offer a destination does nothing for it.
@MainActor
protocol BrowserFileDestinationOpener {
    func openFile(_ fileURL: URL)
    func revealFile(_ fileURL: URL)
    func shareFile(_ fileURL: URL)
    func saveFileToFiles(_ fileURL: URL)
}
