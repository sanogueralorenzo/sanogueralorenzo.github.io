import SwiftUI

struct BrowserCredentialPasswordActions: View {
    let model: BrowserCredentialDetailModel

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: CrestSpacing.medium) {
                Button(
                    model.visiblePassword == nil
                        ? "Reveal Password" : "Hide Password",
                    systemImage: model.visiblePassword == nil ? "eye" : "eye.slash"
                ) {
                    Task { await model.toggleReveal() }
                }
                .buttonStyle(BrowserSettingsLabeledActionButtonStyle())
                .disabled(model.isAuthenticating)
                .accessibilityIdentifier("reveal-credential-password")

                Button("Copy Password", systemImage: "doc.on.doc") {
                    Task { await model.copy() }
                }
                .buttonStyle(BrowserSettingsLabeledActionButtonStyle())
                .disabled(model.isAuthenticating)
                .accessibilityIdentifier("copy-credential-password")
            }

            VStack(spacing: CrestSpacing.medium) {
                Button(
                    model.visiblePassword == nil
                        ? "Reveal Password" : "Hide Password",
                    systemImage: model.visiblePassword == nil ? "eye" : "eye.slash"
                ) {
                    Task { await model.toggleReveal() }
                }
                .buttonStyle(BrowserSettingsLabeledActionButtonStyle())
                .disabled(model.isAuthenticating)
                .accessibilityIdentifier("reveal-credential-password")

                Button("Copy Password", systemImage: "doc.on.doc") {
                    Task { await model.copy() }
                }
                .buttonStyle(BrowserSettingsLabeledActionButtonStyle())
                .disabled(model.isAuthenticating)
                .accessibilityIdentifier("copy-credential-password")
            }
        }
    }
}

#if DEBUG
    #Preview("Reveal and copy") {
        Form { BrowserCredentialPasswordActions(model: BrowserCredentialDetailPreviewFixture.makeModel()) }
            .crestSettingsForm().frame(width: 420, height: 180)
    }
#endif
