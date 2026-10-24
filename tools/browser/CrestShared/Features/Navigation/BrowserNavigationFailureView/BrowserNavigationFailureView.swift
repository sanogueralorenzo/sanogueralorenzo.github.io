import SwiftUI

struct BrowserNavigationFailureView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let failure: PageFailure
    let branding: SpaceBranding?
    let layout: BrowserNavigationFailureLayout
    let canGoBack: Bool
    let canProceed: Bool
    let retry: () -> Void
    let goBack: () -> Void
    let proceed: () -> Void

    @ScaledMetric(relativeTo: .title) private var iconSize =
        BrowserNavigationFailureMetrics.iconSize
    @State private var showsDetails = false

    private var accent: Color {
        BrowserNavigationFailureAppearance.brandColor(for: branding)?.color
            ?? .accentColor
    }

    private var presentation: BrowserNavigationFailurePresentation {
        BrowserNavigationFailurePresentation(failure: failure)
    }

    var body: some View {
        ScrollView {
            BrowserNavigationFailureContent(
                failure: failure,
                presentation: presentation,
                layout: layout,
                canGoBack: canGoBack,
                canProceed: canProceed,
                showsDetails: showsDetails,
                accent: accent,
                iconSize: iconSize,
                retry: retry,
                goBack: goBack,
                proceed: proceed,
                toggleDetails: toggleDetails
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("navigation-failure")
    }

    private func toggleDetails() {
        withAnimation(
            CrestMotion.recovery.unlessReducingMotion(reduceMotion)
        ) {
            showsDetails.toggle()
        }
    }
}

#Preview(
    "Navigation Failure — Compact",
    traits: .fixedLayout(width: 390, height: 700)
) {
    BrowserNavigationFailureView(
        failure: BrowserNavigationFailurePreviewFixture.offline,
        branding: BrowserNavigationFailurePreviewFixture.branding,
        layout: .compact,
        canGoBack: true,
        canProceed: false,
        retry: {},
        goBack: {},
        proceed: {}
    )
}

#Preview(
    "Navigation Failure — Regular Dark",
    traits: .fixedLayout(width: 900, height: 700)
) {
    BrowserNavigationFailureView(
        failure: BrowserNavigationFailurePreviewFixture.certificate,
        branding: BrowserNavigationFailurePreviewFixture.branding,
        layout: .regular,
        canGoBack: true,
        canProceed: true,
        retry: {},
        goBack: {},
        proceed: {}
    )
    .preferredColorScheme(.dark)
}
