import SwiftUI

struct BrowserDataPortabilityExportControls: View {
    let model: BrowserDataPortabilityModel

    var body: some View {
        Button("Export Browser Data…") {
            model.prepareExport(.browserData)
        }
        .disabled(model.preparingFormat != nil)
        .accessibilityIdentifier("export-browser-data")

        Button("Import Browser Data…") {
            model.beginImport()
        }
        .accessibilityIdentifier("import-browser-data")
        Button("Export Bookmarks as HTML…") {
            model.prepareExport(.bookmarks)
        }
        .disabled(model.preparingFormat != nil)
        .accessibilityIdentifier("export-bookmarks-html")
    }
}
