import SwiftUI

struct BrowserSpaceAddButton: View {
    let action: () -> Void

    var body: some View {
        GlassEffectContainer {
            BrowserSpaceSettingsGlassButton(title: "New Space", symbol: "plus", action: action)
                .help("New Space")
                .accessibilityIdentifier("space-settings-add")
        }
        .fixedSize()
    }
}

#if DEBUG
    #Preview("Component") {
        BrowserSpaceAddButton(action: {}).padding()
    }
#endif
