import SwiftUI

struct BrowserSiteControlHeader: View {
    let page: BrowserPage

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(page.live.title.isEmpty ? "Site Controls" : page.live.title)
                .font(.headline)
                .lineLimit(1)
            if let host = page.live.displayURL?.host() {
                Text(host)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}
