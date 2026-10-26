import SwiftUI

struct BrowserNavigationFailureActions: View {
    let layout: BrowserNavigationFailureLayout
    let canGoBack: Bool
    let canProceed: Bool
    let showsDetails: Bool
    let accent: Color
    let retry: () -> Void
    let goBack: () -> Void
    let proceed: () -> Void
    let toggleDetails: () -> Void

    @ViewBuilder
    var body: some View {
        if layout.stacksActions {
            VStack(spacing: CrestSpacing.medium) {
                BrowserNavigationFailureRetryButton(
                    accent: accent,
                    action: retry
                )
                .frame(maxWidth: .infinity)

                if canProceed {
                    BrowserNavigationFailureProceedButton(action: proceed)
                        .frame(maxWidth: .infinity)
                }

                if canGoBack {
                    BrowserNavigationFailureBackButton(action: goBack)
                        .frame(maxWidth: .infinity)
                }

                BrowserNavigationFailureDetailsButton(
                    showsDetails: showsDetails,
                    action: toggleDetails
                )
                .frame(maxWidth: .infinity)
            }
        } else {
            HStack(spacing: CrestSpacing.medium) {
                BrowserNavigationFailureDetailsButton(
                    showsDetails: showsDetails,
                    action: toggleDetails
                )

                if canGoBack {
                    BrowserNavigationFailureBackButton(action: goBack)
                }

                Spacer(minLength: CrestSpacing.extraExtraLarge)

                if canProceed {
                    BrowserNavigationFailureProceedButton(action: proceed)
                }

                BrowserNavigationFailureRetryButton(
                    accent: accent,
                    action: retry
                )
            }
        }
    }
}
