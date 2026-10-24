import SwiftUI

struct BrowserCredentialErrorSection: View {
    let message: String?

    var body: some View {
        if let message {
            Section {
                Label(
                    message,
                    systemImage: "exclamationmark.triangle.fill"
                )
                .foregroundStyle(.red)
            }
        }
    }
}

#if DEBUG
    #Preview("Component") {
        Form { BrowserCredentialErrorSection(message: "Unable to unlock this password. Try again.") }
            .crestSettingsForm().frame(width: 400, height: 160)
    }
#endif
