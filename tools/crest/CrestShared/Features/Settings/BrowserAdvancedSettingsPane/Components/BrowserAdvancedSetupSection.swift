import SwiftUI

struct BrowserAdvancedSetupSection: View {
    let setupActions: [BrowserAdvancedSetupAction]

    var body: some View {
        Section("Setup") {
            ForEach(setupActions) { setupAction in
                BrowserAdvancedSetupActionButton(setupAction: setupAction)
            }
        }
    }
}
