import Foundation
import UniformTypeIdentifiers

extension DownloadRiskFacts {
    /// The platform's file-system-safe name and type-registry facts for a
    /// download. The core decides the risk reasons and whether confirmation
    /// is needed.
    init(suggestedFilename: String, mimeType: String?) {
        let sanitizedFilename = BrowserDownloadDestination.safeFilename(from: suggestedFilename)
        let extensionType = Self.contentType(forFilename: sanitizedFilename)
        let declaredMIMEType = mimeType?.lowercased()
        let mimeContentType = declaredMIMEType.flatMap {
            UTType(tag: $0, tagClass: .mimeType, conformingTo: nil)
        }
        let typesRelated: Bool? = extensionType.flatMap { extensionType in
            mimeContentType.map {
                extensionType.conforms(to: $0) || $0.conforms(to: extensionType)
            }
        }
        self.init(
            suggestedFilename: suggestedFilename,
            sanitizedFilename: sanitizedFilename,
            mimeType: declaredMIMEType,
            extensionRunsCode: Self.runsCode(extensionType),
            mimeTypeRunsCode: Self.runsCode(mimeContentType),
            typesRelated: typesRelated
        )
    }

    private static func contentType(forFilename filename: String) -> UTType? {
        let pathExtension = (filename as NSString).pathExtension
        guard !pathExtension.isEmpty else { return nil }
        return UTType(filenameExtension: pathExtension)
    }

    private static func runsCode(_ type: UTType?) -> Bool {
        guard let type else { return false }
        return type.conforms(to: .executable)
            || type.conforms(to: .application)
            || type.conforms(to: .script)
            || type.conforms(to: .diskImage)
    }
}
