import SwiftUI

struct MobileOnboardingPage<Content: View>: View {
    let progressIndex: Int?
    let primaryTitle: String
    let primarySystemImage: String
    let primaryIdentifier: String
    var primaryDisabled = false
    var showsActivity = false
    var secondaryTitle: String?
    var secondaryIdentifier: String?
    var secondaryAction: (() -> Void)?
    let primaryAction: () -> Void
    var scrolls = true
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            MobileOnboardingProgressIndicator(currentIndex: progressIndex)
                .padding(
                    .horizontal,
                    MobileOnboardingLayout.pageProgressHorizontalPadding
                )
                .padding(.top, MobileOnboardingLayout.pageProgressTopPadding)
                .padding(.bottom, MobileOnboardingLayout.pageProgressBottomPadding)

            if scrolls {
                ScrollView {
                    pageContent
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
            } else {
                pageContent
            }

            MobileOnboardingPageActions(
                primaryTitle: primaryTitle,
                primarySystemImage: primarySystemImage,
                primaryIdentifier: primaryIdentifier,
                primaryDisabled: primaryDisabled,
                showsActivity: showsActivity,
                secondaryTitle: secondaryTitle,
                secondaryIdentifier: secondaryIdentifier,
                secondaryAction: secondaryAction,
                primaryAction: primaryAction
            )
            .padding(.top, MobileOnboardingLayout.pageActionsTopPadding)
            .padding(.bottom, MobileOnboardingLayout.pageActionsBottomPadding)
        }
    }

    private var pageContent: some View {
        content
            .frame(maxWidth: MobileOnboardingLayout.pageContentMaximumWidth)
            .frame(maxWidth: .infinity)
            .padding(
                .horizontal,
                MobileOnboardingLayout.pageContentHorizontalPadding
            )
            .padding(.vertical, MobileOnboardingLayout.pageContentVerticalPadding)
    }
}
