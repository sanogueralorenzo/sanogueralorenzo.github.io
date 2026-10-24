import SwiftUI

struct BrowserAdvancedSetupActionButton: View {
    let setupAction: BrowserAdvancedSetupAction

    @ViewBuilder
    var body: some View {
        if let help = setupAction.help {
            button.help(help)
        } else {
            button
        }
    }

    private var button: some View {
        Button(setupAction.title) {
            setupAction.action()
        }
        .crestAccessibilityIdentifier(setupAction.identifier)
    }
}
