import SwiftUI

struct BrowserCredentialCopyConfirmation: View {
    let isPresented: Bool

    var body: some View {
        if isPresented {
            Label(
                "Copied locally for 60 seconds",
                systemImage: "checkmark.circle.fill"
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
    }
}

#if DEBUG
    #Preview("Component") {
        BrowserCredentialCopyConfirmation(isPresented: true).padding()
    }
#endif
