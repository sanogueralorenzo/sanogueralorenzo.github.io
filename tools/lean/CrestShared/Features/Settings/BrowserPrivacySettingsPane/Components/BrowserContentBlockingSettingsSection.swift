import SwiftUI

struct BrowserContentBlockingSettingsSection: View {
    @Binding var policy: ContentBlockingPolicy
    let errorDescription: String?

    var body: some View {
        Section("Content blocking") {
            Toggle("Block known ads and trackers", isOn: isEnabled)
                .accessibilityIdentifier("content-blocking-enabled")

            if policy.blocksContent, let errorDescription {
                Label(
                    errorDescription,
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.footnote)
                .foregroundStyle(.orange)
            }
        }
    }

    private var isEnabled: Binding<Bool> {
        Binding {
            policy.blocksContent
        } set: { isEnabled in
            policy = .blocking(isEnabled)
        }
    }
}
