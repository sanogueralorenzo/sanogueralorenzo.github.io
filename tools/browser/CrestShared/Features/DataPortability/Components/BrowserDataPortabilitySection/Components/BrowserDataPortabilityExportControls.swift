import SwiftUI

struct BrowserDataPortabilityExportControls: View {
    let model: BrowserDataPortabilityModel

    var body: some View {
        if model.lockedSpaces.isEmpty {
            Button("Export Browser Data…") {
                model.prepareExport(.browserData)
            }
            .disabled(model.preparingFormat != nil)
            .accessibilityIdentifier("export-browser-data")
        } else {
            Text("Unlock these Spaces to export their tabs and history.")
                .foregroundStyle(.secondary)

            ForEach(model.lockedSpaces) { space in
                BrowserSettingsPrivateSpaceAccessRow(
                    space: space,
                    accessController: model.spaceAccess
                )
            }
        }

        Button("Import Browser Data…") {
            model.beginImport()
        }
        .accessibilityIdentifier("import-browser-data")

        if model.lockedSpaces.isEmpty {
            Button("Export Bookmarks as HTML…") {
                model.prepareExport(.bookmarks)
            }
            .disabled(model.preparingFormat != nil)
            .accessibilityIdentifier("export-bookmarks-html")
        }
    }
}
