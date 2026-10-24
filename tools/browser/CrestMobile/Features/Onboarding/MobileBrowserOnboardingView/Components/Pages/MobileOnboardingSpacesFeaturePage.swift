import SwiftUI

struct MobileOnboardingSpacesFeaturePage: View {
    let previewWidth: CGFloat
    let personalSpace: SpaceModel
    let workSpace: SpaceModel
    let secondaryTitle: String?
    let secondaryAction: (() -> Void)?
    let primaryAction: () -> Void

    var body: some View {
        MobileOnboardingPage(
            progressIndex: 0,
            primaryTitle: "Continue",
            primarySystemImage: "chevron.right",
            primaryIdentifier:
                BrowserMobileAccessibilityID.featureNext,
            secondaryTitle: secondaryTitle,
            secondaryIdentifier:
                BrowserMobileAccessibilityID.close,
            secondaryAction: secondaryAction,
            primaryAction: primaryAction
        ) {
            VStack(spacing: MobileOnboardingLayout.featurePageSpacing) {
                MobileOnboardingTitle(
                    title: "Everything in its Space",
                    detail: "Each Space is its own browser, with a sidebar that always reflects where you are."
                )

                MobileOnboardingLayeredSpacePreview(
                    previewWidth: previewWidth,
                    personalSpace: personalSpace,
                    workSpace: workSpace
                )
                .accessibilityIdentifier(
                    BrowserMobileAccessibilityID.spacesFeature
                )

                Label(
                    "Swipe between Spaces",
                    systemImage: "arrow.left.and.right"
                )
                .font(.callout.weight(.semibold))
                .foregroundStyle(.secondary)
            }
        }
    }
}
