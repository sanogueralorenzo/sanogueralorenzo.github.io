import SwiftUI

struct BrowserNavigationFailureBackButton: View {
    let action: () -> Void

    var body: some View {
        Button("Go Back", systemImage: "chevron.backward", action: action)
            .buttonStyle(.bordered)
            .controlSize(.large)
            .accessibilityHint("Returns to the last page")
            .accessibilityIdentifier("navigation-failure-back")
    }
}

#if DEBUG
    #Preview("Component") {
        BrowserNavigationFailureBackButton(action: {}).padding()
    }
#endif
