import SwiftUI

struct BrowserCredentialDetailContent: View {
    let model: BrowserCredentialDetailModel
    let dismiss: () -> Void

    var body: some View {
        Form {
            BrowserCredentialAccountSection(
                descriptor: model.descriptor,
                spaceName: model.spaceName
            )
            BrowserCredentialPasswordSection(model: model)
            BrowserCredentialErrorSection(message: model.errorMessage)
        }
        .formStyle(.grouped)
        .accessibilityIdentifier("credential-detail-form")
        .navigationTitle(
            model.descriptor.displayName ?? model.descriptor.username
        )
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done", action: dismiss)
            }
        }
    }
}
