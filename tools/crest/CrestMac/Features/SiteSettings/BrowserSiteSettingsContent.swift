import SwiftUI

struct BrowserSiteSettingsContent: View {
    let page: BrowserPage
    let permissionCenter: BrowserSitePermissionCenter
    var reviewCertificate: (() -> Void)?
    var body: some View {
        VStack(alignment: .leading, spacing: CrestSpacing.medium) {
            BrowserSiteDeveloperModeStatus(page: page)

            if let origin {
                BrowserSiteOriginSettings(
                    page: page,
                    origin: origin,
                    reviewCertificate: reviewCertificate,
                    permissionCenter: permissionCenter
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
    let preview = BrowserSiteSettingsPreviewFixture.makePage()
    BrowserSiteSettingsContent(
        page: preview.page,
        permissionCenter: preview.permissionCenter
    )
    .padding()
    .frame(width: 300)
}
