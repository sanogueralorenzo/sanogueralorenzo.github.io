import SwiftUI

struct MobileOnboardingSyncFeaturePage: View {
    let secondaryTitle: String?
    let secondaryAction: (() -> Void)?
    let primaryAction: () -> Void

    var body: some View {
        MobileOnboardingPage(
            progressIndex: 2,
            primaryTitle: "Set Up Spaces",
            primarySystemImage: "chevron.right",
            primaryIdentifier:
                BrowserMobileAccessibilityID.featureNext,
            secondaryTitle: secondaryTitle,
            secondaryIdentifier:
                BrowserMobileAccessibilityID.close,
            secondaryAction: secondaryAction,
            primaryAction: primaryAction
        ) {
            VStack(spacing: MobileOnboardingLayout.syncFeaturePageSpacing) {
                MobileOnboardingTitle(
                    title: "Yours on every device",
                    detail: "Crest syncs privately with iCloud while keeping every Space isolated."
                )

                Image(systemName: "laptopcomputer.and.iphone")
                    .font(
                        .system(
                            size: MobileOnboardingLayout.syncSymbolSize,
                            weight: .light
                        )
                    )
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.tint)
                    .frame(
                        width: MobileOnboardingLayout.syncSymbolFrame,
                        height: MobileOnboardingLayout.syncSymbolFrame
                    )
                    .background(
                        Color(uiColor: .secondarySystemBackground),
                        in: .circle
                    )
                    .accessibilityHidden(true)

                VStack(spacing: 0) {
                    MobileOnboardingFeatureRow(
                        symbol: "lock.shield.fill",
                        title: "Private by design",
                        detail: "History, passwords, and site data never leak between Spaces."
                    )
                    Divider()
                    MobileOnboardingFeatureRow(
                        symbol: "laptopcomputer",
                        title: "Import on macOS",
                        detail: "Review imports on your Mac, then let iCloud bring the result to mobile."
                    )
                }
                .frame(maxWidth: MobileOnboardingLayout.featureListMaximumWidth)
                .accessibilityIdentifier(
                    BrowserMobileAccessibilityID.syncFeatureList
                )
            }
        }
    }
}

#if DEBUG
    #Preview("Component") {
        MobileOnboardingSyncFeaturePage(secondaryTitle: "Back", secondaryAction: {}, primaryAction: {}).frame(
            width: 390, height: 844)
    }
#endif
