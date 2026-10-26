import SwiftUI

struct BrowserSiteOriginSettings: View {
    let page: BrowserPage
    let origin: SiteOrigin
    var reviewCertificate: (() -> Void)?
    let permissionCenter: BrowserSitePermissionCenter

    var body: some View {
        VStack(alignment: .leading, spacing: CrestSpacing.medium) {
            Divider()
            BrowserSiteSecuritySection(
                page: page,
                origin: origin,
                reviewCertificate: reviewCertificate
            )
            Divider()
            BrowserEngineSitePermissionsSection(
                page: page,
                origin: origin,
                permissionCenter: permissionCenter
            )
        }
    }
}
