import SwiftUI

struct BrowserNavigationFailureContent: View {
    let failure: PageFailure
    let presentation: BrowserNavigationFailurePresentation
    let layout: BrowserNavigationFailureLayout
    let canGoBack: Bool
    let canProceed: Bool
    let showsDetails: Bool
    let accent: Color
    let iconSize: CGFloat
    let retry: () -> Void
    let goBack: () -> Void
    let proceed: () -> Void
    let toggleDetails: () -> Void

    var body: some View {
        VStack(
            alignment: layout.contentAlignment,
            spacing: BrowserNavigationFailureMetrics.contentSpacing
        ) {
            BrowserNavigationFailureStatusIcon(
                symbolName: presentation.symbolName,
                accent: accent,
                iconSize: iconSize
            )
            BrowserNavigationFailureHeadline(
                failure: failure,
                presentation: presentation,
                alignment: layout.contentAlignment,
                textAlignment: layout.textAlignment
            )
            BrowserNavigationFailureSuggestions(
                presentation: presentation,
                accent: accent
            )
            BrowserNavigationFailureActions(
                layout: layout,
                canGoBack: canGoBack,
                canProceed: canProceed,
                showsDetails: showsDetails,
                accent: accent,
                retry: retry,
                goBack: goBack,
                proceed: proceed,
                toggleDetails: toggleDetails
            )
            if showsDetails {
                BrowserNavigationFailureTechnicalDetails(failure: failure)
                    .transition(.opacity)
            }
        }
        .frame(
            maxWidth: BrowserNavigationFailureMetrics.maximumContentWidth,
            alignment: layout.frameAlignment
        )
        .padding(.horizontal, layout.horizontalPadding)
        .padding(.vertical, layout.verticalPadding)
        .frame(maxWidth: .infinity, alignment: .center)
    }
}
