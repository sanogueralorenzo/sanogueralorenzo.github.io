import SwiftUI

/// Activity replaces the label without changing the native button's geometry.
struct BrowserSpaceAccessActionLabel: View {
    let isAuthenticating: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                Text("Unlock")
            } else {
                Label("Unlock", systemImage: "lock.open.fill")
            }
        }
        .font(.body.weight(.semibold))
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity)
        .opacity(isAuthenticating ? 0 : 1)
        .overlay {
            if isAuthenticating {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .accessibilityHidden(true)
    }
}

#if DEBUG
    #Preview("Unlock and authenticating") {
        VStack(spacing: 20) {
            BrowserSpaceAccessActionLabel(isAuthenticating: false)
            BrowserSpaceAccessActionLabel(isAuthenticating: true)
        }.padding()
    }
#endif
