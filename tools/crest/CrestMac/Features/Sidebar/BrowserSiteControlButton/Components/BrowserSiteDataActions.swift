import SwiftUI

/// Clearing the site's cookies or its cache in the page's Space. Each runs at
/// once, reloads the page and says at the top of the window how it went.
struct BrowserSiteDataActions: View {
    let page: BrowserPage
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: CrestSpacing.small) {
            ForEach(BrowsingDataCategory.all.filter(\.clearsBySite), id: \.self) { category in
                Button {
                    dismiss()
                    Task { await page.clearSiteData(category) }
                } label: {
                    Label {
                        Text(category.clearSiteTitle ?? category.title)
                    } icon: {
                        Image(systemName: category.symbol ?? "trash")
                    }
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                    .frame(height: BrowserSiteControlMetrics.quickActionHeight)
                }
                .buttonStyle(
                    CrestChromeButtonStyle(controlSize: nil, cornerRadius: CrestRadius.compact, showsRestingFill: true)
                )
            }
        }
    }
}
