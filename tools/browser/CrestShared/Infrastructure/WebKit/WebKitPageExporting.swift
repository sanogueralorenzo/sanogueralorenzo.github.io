import Foundation

/// Makes a page's document in each format an export may ask for, and
/// presents it once made. Each method answers whether it began; one for a
/// format the engine cannot make answers false.
@MainActor
protocol WebKitPageExporting {
    func exportPDF(_ exporting: ExportPage, from page: WebKitEnginePage) -> Bool
    func exportPNG(_ exporting: ExportPage, from page: WebKitEnginePage) -> Bool
    func exportMHTML(_ exporting: ExportPage, from page: WebKitEnginePage) -> Bool
    func exportWebArchive(_ exporting: ExportPage, from page: WebKitEnginePage) -> Bool
}
