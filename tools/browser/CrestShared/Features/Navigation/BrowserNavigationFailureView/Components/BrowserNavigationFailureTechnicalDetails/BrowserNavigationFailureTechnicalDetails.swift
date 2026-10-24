import SwiftUI

struct BrowserNavigationFailureTechnicalDetails: View {
    let failure: PageFailure

    var body: some View {
        VStack(alignment: .leading, spacing: CrestSpacing.medium) {
            Text("Technical Details")
                .font(.headline)

            if let failingURL = failure.failingURL {
                BrowserNavigationFailureDetailRow(
                    label: "Address",
                    value: failingURL.absoluteString
                )
            }
            BrowserNavigationFailureDetailRow(
                label: "Error Domain",
                value: failure.domain
            )
            BrowserNavigationFailureDetailRow(
                label: "Error Number",
                value: String(failure.code)
            )
            BrowserNavigationFailureDetailRow(
                label: "Loading Stage",
                value: !failure.replacedDocument
                    ? String(localized: "Before content loaded")
                    : String(localized: "After content started loading")
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(BrowserNavigationFailureMetrics.surfacePadding)
        .background(
            .primary.opacity(BrowserNavigationFailureMetrics.surfaceOpacity),
            in: .rect(
                cornerRadius: BrowserNavigationFailureMetrics.surfaceCornerRadius
            )
        )
        .textSelection(.enabled)
    }
}

#if DEBUG
    #Preview("Component") {
        BrowserNavigationFailureTechnicalDetails(failure: BrowserNavigationFailurePreviewFixture.certificate).padding()
            .frame(width: 460)
    }
#endif
