import SwiftUI

struct BrowserAdvancedImportSection: View {
    let importActions: [BrowserAdvancedImportAction]

    var body: some View {
        if !importActions.isEmpty {
            Section("Import") {
                ForEach(importActions) { importAction in
                    BrowserAdvancedImportActionButton(importAction: importAction)
                }
            }
        }
    }
}
