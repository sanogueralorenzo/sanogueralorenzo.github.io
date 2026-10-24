import SwiftUI

struct BrowserCredentialAccountSection: View {
    let descriptor: CredentialDescriptor
    let spaceName: String

    var body: some View {
        Section("Account") {
            LabeledContent("Website", value: descriptor.origin.description)
            LabeledContent("Username", value: descriptor.username)
            if let scope = descriptor.scope.settingsLabel {
                LabeledContent("Type", value: scope)
            }
            LabeledContent("Space", value: spaceName)
            if !descriptor.origin.isSecure {
                Label(
                    "This password was imported from an insecure HTTP site. Crest keeps it available to view or copy but will not autofill it on an insecure connection.",
                    systemImage: "exclamationmark.shield.fill"
                )
                .font(.footnote)
                .foregroundStyle(.orange)
            }
        }
    }
}

#if DEBUG
    #Preview("Component") {
        Form {
            BrowserCredentialAccountSection(
                descriptor: BrowserCredentialDetailPreviewFixture.descriptor, spaceName: "Design")
        }.crestSettingsForm().frame(width: 420, height: 300)
    }
#endif
