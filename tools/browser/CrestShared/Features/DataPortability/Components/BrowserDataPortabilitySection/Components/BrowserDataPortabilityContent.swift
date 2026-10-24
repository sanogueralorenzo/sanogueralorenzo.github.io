import SwiftUI

struct BrowserDataPortabilityContent: View {
    let model: BrowserDataPortabilityModel
    let showsMacOSImportRequirement: Bool

    var body: some View {
        Section {
            if showsMacOSImportRequirement {
                BrowserDataPortabilityMacRequirement()
            }
            BrowserDataPortabilityExportControls(model: model)
            BrowserDataPortabilityProgressStatus(model: model)
        } header: {
            Text("Import and export")
        } footer: {
            BrowserDataPortabilityFootnotes()
        }
    }
}
