import AppKit
import SwiftUI

struct BrowserSiteControlPopover: View {
    let configuration: BrowserSiteControlConfiguration
    let dismiss: () -> Void

    @State private var isPermissionsExpanded =
        BrowserSitePermissionDisclosure.defaultIsExpanded

    var body: some View {
        ScrollView {
            BrowserSiteControlContent(
                configuration: configuration,
                permissionsExpansion: $isPermissionsExpanded,
                dismiss: dismiss,
                reviewCertificate: reviewCertificate
            )
        }
        .id(isPermissionsExpanded)
        .frame(
            width: BrowserSiteControlMetrics.width,
            height: isPermissionsExpanded ? BrowserSiteControlMetrics.expandedHeight : nil
        )
        .frame(maxHeight: BrowserSiteControlMetrics.maximumHeight)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Site Controls")
        .accessibilityIdentifier("browser-site-controls-popover")
        .onAppear {
            if configuration.page.blockedPopupNotice != nil {
                isPermissionsExpanded = true
            }
        }
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
