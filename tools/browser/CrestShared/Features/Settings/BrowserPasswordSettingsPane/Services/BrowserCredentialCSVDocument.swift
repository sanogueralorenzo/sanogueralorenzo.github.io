import SwiftUI
import UniformTypeIdentifiers

/// A password file the core wrote, for the file exporter to save.
struct BrowserCredentialCSVDocument: FileDocument {
    // MARK: - Static Variables

    static let readableContentTypes: [UTType] = [.commaSeparatedText]

    // MARK: - Variables

    let data: Data

    // MARK: - Initializers

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }

    // MARK: - Actions - Writing

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
