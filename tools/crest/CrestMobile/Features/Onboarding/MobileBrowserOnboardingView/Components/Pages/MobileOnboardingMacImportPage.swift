import SwiftUI

struct MobileOnboardingMacImportPage: View {
    let close: () -> Void
    let reviewFeatures: () -> Void

    var body: some View {
        MobileOnboardingPage(
            progressIndex: nil,
            primaryTitle: "Review Features",
            primarySystemImage: "chevron.right",
            primaryIdentifier:
                BrowserMobileAccessibilityID
                .macImportReviewFeatures,
            secondaryTitle: "Close",
            secondaryIdentifier:
                BrowserMobileAccessibilityID.close,
            secondaryAction: close,
            primaryAction: reviewFeatures
        ) {
            VStack(spacing: MobileOnboardingLayout.macImportPageSpacing) {
                Spacer(
                    minLength: MobileOnboardingLayout.macImportMinimumSpacing
                )

                HStack(spacing: MobileOnboardingLayout.macImportSymbolSpacing) {
                    Image(systemName: "laptopcomputer")
                    Image(systemName: "icloud.fill")
                        .foregroundStyle(.tint)
                    Image(systemName: "iphone")
                }
                .font(
                    .system(
                        size: MobileOnboardingLayout.macImportSymbolSize,
                        weight: .light
                    )
                )
                .accessibilityHidden(true)

                MobileOnboardingTitle(
                    title: "Import with Crest on macOS",
                    detail:
                        "A Mac can securely read installed browsers. Review every Space and tab there, then sync the result here with iCloud."
                )
                .accessibilityIdentifier(
                    BrowserMobileAccessibilityID.macImportContent
                )

                Text("You can still create and rename Spaces on this device.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Spacer(
                    minLength: MobileOnboardingLayout.macImportMinimumSpacing
                )
            }
        }
    }
}

#if DEBUG
    #Preview("Component") {
        MobileOnboardingMacImportPage(close: {}, reviewFeatures: {}).frame(width: 390, height: 844)
    }
#endif
