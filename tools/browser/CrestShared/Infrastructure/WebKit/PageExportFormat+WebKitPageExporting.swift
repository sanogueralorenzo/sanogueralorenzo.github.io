import Foundation

extension PageExportFormat {
    /// Makes `page`'s document in this format through `exporter`, as the
    /// export asks. Answers whether the export began.
    @MainActor func export(
        _ exporting: ExportPage, from page: WebKitEnginePage, using exporter: some WebKitPageExporting
    ) -> Bool {
        switch self {
        case .pdf: exporter.exportPDF(exporting, from: page)
        case .png: exporter.exportPNG(exporting, from: page)
        case .mhtml: exporter.exportMHTML(exporting, from: page)
        case .webArchive: exporter.exportWebArchive(exporting, from: page)
        }
    }
}
