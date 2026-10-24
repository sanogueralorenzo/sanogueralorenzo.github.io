import SwiftUI

struct BrowserCredentialPasswordSection: View {
    let model: BrowserCredentialDetailModel

    var body: some View {
        Section("Password") {
            HStack(spacing: CrestSpacing.medium) {
                BrowserCredentialPasswordValue(
                    password: model.visiblePassword
                )

                Spacer(minLength: CrestSpacing.small)

                if model.isAuthenticating {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            BrowserCredentialPasswordActions(model: model)
            BrowserCredentialCopyConfirmation(
                isPresented: model.showsCopyConfirmation
            )

            Text(
                "Crest requires Touch ID, Face ID, or the device password before every reveal or copy. A revealed password hides after 30 seconds; a copied password expires after 60 seconds."
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
    }
}
