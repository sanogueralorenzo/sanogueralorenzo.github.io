import SwiftUI

struct BrowserOnboardingWelcomeCallToAction: View {
    let action: BrowserOnboardingWelcomeAction
    let cloudStatusDetail: String
    let perform: () -> Void
    let setUpWithoutCloud: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: perform) {
                HStack(spacing: 10) {
                    if action.waitsOnCloud {
                        ProgressView().controlSize(.small)
                    }
                    Text(action.opensCrest ? "Open Crest" : "Continue")
                    Image(systemName: "arrow.right")
                }
                .frame(minWidth: 120)
            }
            .buttonStyle(.crestPrimary)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .disabled(action.waitsOnCloud)
            .accessibilityLabel(
                action.opensCrest ? Text("Open Crest") : Text("Continue")
            )
            .accessibilityIdentifier("onboarding-welcome-continue")

            Text(
                action.waitsOnCloud
                    ? String(localized: "Checking iCloud for an existing setup…")
                    : cloudStatusDetail
            )
            .font(CrestTypography.sans(12, weight: .medium))
            .foregroundStyle(CrestBrandTheme.textDisplay.opacity(0.6))

            if action.offersSetupWithoutCloud {
                Button("Set Up Without iCloud", action: setUpWithoutCloud)
                    .buttonStyle(.crestTertiary)
                    .accessibilityIdentifier("onboarding-welcome-setup-without-icloud")
            }
        }
    }
}
