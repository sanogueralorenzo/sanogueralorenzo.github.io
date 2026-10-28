import Foundation
import UniformTypeIdentifiers

/// The archive a page's engine keeps a document and its resources in. Each
/// engine declares its own in its registration, so nothing here names an
/// engine: Chromium reads the MHTML it writes and cannot read a WebKit
/// `.webarchive`.
struct BrowserPageArchiveFormat: Hashable, Sendable {
    // MARK: - Static Variables

    static let webArchive = Self(pathExtension: "webarchive", exportFormat: .webArchive)
    static let mhtml = Self(pathExtension: "mhtml", exportFormat: .mhtml)

    /// The format of the engine this process registered, for the moments before a
    /// page exists to ask. The command route still prefers the active page's own
    /// engine when there is one. The value comes from the engine's own
    /// registration rather than a compile-time condition repeated here.
    static var registered: BrowserPageArchiveFormat {
        BrowserEngineRegistration.current.archiveFormat
    }

    // MARK: - Variables

    /// The extension an archive in this format is saved with.
    let pathExtension: String
    /// What the page's engine exports an archive as.
    let exportFormat: PageExportFormat

    /// The file type an archive in this format is saved and opened as.
    var contentType: UTType {
        UTType(filenameExtension: pathExtension) ?? .data
    }

    /// What the Open File panel offers while this format's engine is running.
    ///
    /// The archive entry follows the engine rather than the platform, so the
    /// panel never advertises a document the running engine has no reader for.
    var openableContentTypes: [UTType] {
        var types: [UTType] = [.html]
        if let xhtml = UTType("public.xhtml") { types.append(xhtml) }
        types.append(contentsOf: [.pdf, .plainText, .image])
        types.append(contentType)
        return types
    }
}
