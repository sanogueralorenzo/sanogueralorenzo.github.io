import SwiftUI

struct BrowserSiteSettingsContent: View {
    let page: BrowserPage
    let permissionCenter: BrowserSitePermissionCenter
    var reviewCertificate: (() -> Void)?
    @Binding private var isPermissionsExpanded: Bool

    init(
        page: BrowserPage,
        permissionCenter: BrowserSitePermissionCenter,
        reviewCertificate: (() -> Void)? = nil,
        permissionsExpansion: Binding<Bool>
    ) {
        self.page = page
        self.permissionCenter = permissionCenter
        self.reviewCertificate = reviewCertificate
        _isPermissionsExpanded = permissionsExpansion
    }

    var body: some View {
        VStack(alignment: .leading, spacing: CrestSpacing.medium) {
            BrowserSiteDeveloperModeStatus(page: page)

            if let origin {
                BrowserSiteEngineRow(page: page, origin: origin)
                BrowserSiteOriginSettings(
                    page: page,
                    origin: origin,
                    reviewCertificate: reviewCertificate,
                    permissionCenter: permissionCenter,
                    isExpanded: $isPermissionsExpanded
                )
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Site Settings")
    }

    private var origin: SiteOrigin? {
        page.live.displayURL.flatMap(SiteOrigin.init(url:))
    }
}

#Preview("Site Settings") {
    @Previewable @State var isExpanded = true
    let preview = BrowserSiteSettingsPreviewFixture.makePage()
    BrowserSiteSettingsContent(
        page: preview.page,
        permissionCenter: preview.permissionCenter,
        permissionsExpansion: $isExpanded
    )
    .padding()
    .frame(width: 300)
}
