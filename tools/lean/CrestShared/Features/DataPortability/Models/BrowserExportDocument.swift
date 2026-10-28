import SwiftUI
import UniformTypeIdentifiers

/// A file the core wrote for an export, as the save panel keeps it.
struct BrowserExportDocument: FileDocument {
    // MARK: - Static Variables

    static let readableContentTypes: [UTType] = ExportFormat.all.map(\.uniformType)

    // MARK: - Variables

    let contents: Data
    let format: ExportFormat

    // MARK: - Initializers

    init(_ document: ExportedDocument) {
        contents = document.contents
        format = document.format
    }

    /// An export is only ever written, so there is never a file to open.
    init(configuration: ReadConfiguration) throws {
        throw CocoaError(.fileReadUnsupportedScheme)
    }

    // MARK: - Actions - Writing

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: contents)
    }
}

extension ExportFormat {
    /// The uniform type the file is saved as.
    var uniformType: UTType {
        UTType(contentType) ?? .data
    }
}
