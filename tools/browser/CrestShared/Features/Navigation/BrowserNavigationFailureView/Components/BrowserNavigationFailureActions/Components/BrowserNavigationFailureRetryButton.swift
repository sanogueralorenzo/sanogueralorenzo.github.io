import SwiftUI

struct BrowserNavigationFailureRetryButton: View {
    let accent: Color
    let action: () -> Void

    var body: some View {
        Button("Try Again", systemImage: "arrow.clockwise", action: action)
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(accent)
            .accessibilityHint("Retries the failed address")
            .accessibilityIdentifier("navigation-failure-retry")
    }
}

#if DEBUG
    #Preview("Component") {
        BrowserNavigationFailureRetryButton(accent: .indigo, action: {}).padding()
    }
#endif
