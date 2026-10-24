import Foundation
import Observation

/// The Import & Export section's work: the core writes each export and reads
/// each Crest browser-data file, and this presents the file panels, holds the
/// access a picked file needs while the core reads it, and reports how it went.
@Observable
@MainActor
final class BrowserDataPortabilityModel {
    // MARK: - Variables

    let browser: BrowserStore
    let spaceAccess: BrowserSpaceAccessController

    /// The file an export is saving, and whether its panel is up.
    var exportDocument: BrowserExportDocument?
    var isExporting = false
    /// The export being written, while the core writes it.
    private(set) var preparingFormat: ExportFormat?
    var isImporting = false
    var status: BrowserDataPortabilityOperationStatus?

    /// The workspace's Spaces that ask for authentication and are locked,
    /// which keep an export from being written.
    var lockedSpaces: [SpaceModel] {
        (browser.workspaceModel?.spaces.models ?? []).filter(spaceAccess.isLocked)
    }

    var lockedSpaceIDs: [UUID] {
        lockedSpaces.map(\.id)
    }

    // MARK: - Initializers

    init(browser: BrowserStore, spaceAccess: BrowserSpaceAccessController) {
        self.browser = browser
        self.spaceAccess = spaceAccess
    }

    // MARK: - Actions - Export

    /// Asks the core for `format`'s file of this workspace, then offers to
    /// save it. A Space locked meanwhile keeps the file from being saved.
    func prepareExport(_ format: ExportFormat) {
        guard lockedSpaces.isEmpty, preparingFormat == nil else { return }
        preparingFormat = format
        status = nil
        let core = browser.core
        let query = ExportWorkspace(workspaceID: browser.family.workspaceID, format: format)
        Task { @MainActor in
            defer { preparingFormat = nil }
            do {
                let document = try await Task.detached(priority: .userInitiated) { try core.query(query) }.value
                guard lockedSpaces.isEmpty else { return }
                exportDocument = BrowserExportDocument(document)
                isExporting = true
            } catch {
                status = BrowserDataPortabilityOperationStatus(error: error)
            }
        }
    }

    func finishExport(_ result: Result<URL, Error>) {
        switch result {
        case .success:
            status = BrowserDataPortabilityOperationStatus((exportDocument?.format ?? .browserData).savedMessage)
        case .failure(let error):
            status = BrowserDataPortabilityOperationStatus(error: error)
        }
        exportDocument = nil
    }

    func cancelSensitiveExports() {
        isExporting = false
        exportDocument = nil
    }

    // MARK: - Actions - Import

    func beginImport() {
        isImporting = true
    }

    /// Imports the Crest browser-data file the person picked: the core reads
    /// it away from the main thread while this holds the file's access, then
    /// adds its Spaces after this workspace's own.
    func finishImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            status = BrowserDataPortabilityOperationStatus("Reading browser data…")
            let core = browser.core
            Task { @MainActor in
                do {
                    let imported = try await Task.detached(priority: .userInitiated) { () throws in
                        let scoped = url.startAccessingSecurityScopedResource()
                        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                        return try core.query(ReadArchive(path: url.path))
                    }.value
                    try browser.importSpaces(imported.spaces)
                    let tabs = imported.spaces.reduce(0) { $0 + $1.tabs.count }
                    let history = imported.spaces.reduce(0) { $0 + $1.history.count }
                    status = BrowserDataPortabilityOperationStatus(
                        "Imported \(imported.spaces.count) Spaces, \(tabs) tabs, and \(history) history entries.")
                } catch {
                    status = BrowserDataPortabilityOperationStatus(error: error)
                }
            }
        case .failure(let error):
            status = BrowserDataPortabilityOperationStatus(error: error)
        }
    }
}
