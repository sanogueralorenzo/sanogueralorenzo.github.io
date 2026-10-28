import SwiftUI

struct BrowserSiteControlContent: View {
    let configuration: BrowserSiteControlConfiguration
    let dismiss: () -> Void
    let reviewCertificate: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: CrestSpacing.medium) {
            BrowserSiteControlHeader(page: configuration.page)
            if let notice = configuration.page.blockedPopupNotice {
                BrowserBlockedPopupSiteControlNotice(
                    notice: notice,
                    allow: {
                        configuration.page.allowAutomaticPopupsForBlockedSite()
                    }
                )
            }
            BrowserSiteQuickActions(
                page: configuration.page,
                dismiss: dismiss
            )
            BrowserEngineSiteControlsSection(
                page: configuration.page,
                space: configuration.space,
                url: configuration.page.live.documentURL,
                dismiss: dismiss
            )
            Divider()
            BrowserSiteSettingsContent(
                page: configuration.page,
                permissionCenter: configuration.permissionCenter,
                reviewCertificate: reviewCertificate
            )
            if configuration.page.live.displayURL?.host()?.isEmpty == false {
                Divider()
                BrowserSiteDataActions(page: configuration.page, dismiss: dismiss)
            }
        }
        .padding(CrestSpacing.medium)
    }
}
