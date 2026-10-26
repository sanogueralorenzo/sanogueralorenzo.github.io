import AppKit
import SwiftUI

struct BrowserSiteControlPopover: View {
    let configuration: BrowserSiteControlConfiguration
    let dismiss: () -> Void

    var body: some View {
        ViewThatFits(in: .vertical) {
            content.fixedSize(horizontal: false, vertical: true)
            ScrollView { content }
                .scrollBounceBehavior(.basedOnSize)
        }
        .frame(width: BrowserSiteControlMetrics.width)
        .frame(maxHeight: BrowserSiteControlMetrics.maximumHeight)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Website Settings")
        .accessibilityIdentifier("browser-site-controls-popover")
    }

    private var content: some View {
        BrowserSiteControlContent(
            configuration: configuration,
            dismiss: dismiss,
            reviewCertificate: reviewCertificate
        )
    }

    private func reviewCertificate() {
        guard let review = configuration.page.certificateReviewAction() else { return }
        dismiss()
        Task { @MainActor in
            await Task.yield()
            review()
        }
    }
}
