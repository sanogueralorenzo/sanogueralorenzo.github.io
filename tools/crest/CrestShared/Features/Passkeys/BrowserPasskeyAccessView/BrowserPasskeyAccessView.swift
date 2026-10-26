import SwiftUI

struct BrowserPasskeyAccessView: View {
    /// The app's one passkey controller, shared with the pages that refresh it.
    @Environment(BrowserPasskeyAccessController.self) private var access

    var body: some View {
        VStack(alignment: .leading, spacing: CrestSpacing.medium) {
            HStack(alignment: .top, spacing: CrestSpacing.medium) {
                Label {
                    VStack(
                        alignment: .leading,
                        spacing: CrestSpacing.extraExtraSmall
                    ) {
                        Text(access.status.title)
                            .font(.body.weight(.medium))
                        Text(access.status.detail)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } icon: {
                    Image(systemName: access.status.symbol)
                        .foregroundStyle(statusColor)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("System passkeys: \(String(localized: access.status.title))")
                .accessibilityValue(Text(access.status.detail))
                .accessibilityIdentifier("passkey-access-status")

                Spacer(minLength: CrestSpacing.small)

                if access.isRequesting {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Requesting passkey access")
                }
            }

            if access.canRequestAccess {
                Button("Allow Crest to Use Passkeys…") {
                    Task { await access.requestAccess() }
                }
                .accessibilityIdentifier("request-passkey-access")
            }

            Text("Passkeys can appear in every Space.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .task {
            access.refreshStatus()
        }
    }

    private var statusColor: Color {
        if access.status.isReady { return .green }
        return access.status.needsAttention ? .orange : .secondary
    }
}
