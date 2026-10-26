import SwiftUI

struct BrowserAdvancedImportActionButton: View {
    let importAction: BrowserAdvancedImportAction

    @ViewBuilder
    var body: some View {
        if let help = importAction.help {
            button.help(help)
        } else {
            button
        }
    }

    private var button: some View {
        Button(importAction.title) {
            importAction.action()
        }
        .crestAccessibilityIdentifier(importAction.identifier)
    }
}
