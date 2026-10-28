import SwiftUI

/// One site that keeps data in a Space: its name, what it keeps, and Remove.
struct BrowserWebsiteDataRow: View {
    let site: StoredSite
    let isRemoving: Bool
    let remove: () -> Void

    var body: some View {
        HStack(spacing: CrestFormRowMetrics.contentSpacing) {
            VStack(alignment: .leading, spacing: CrestFormRowMetrics.titleSpacing) {
                Text(site.site)
                    .lineLimit(1)
                Text(kinds)
                    .font(CrestTypography.metadata)
                    .foregroundStyle(CrestColor.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: CrestSpacing.small)
            Button("Remove", action: remove)
                .disabled(isRemoving)
                .accessibilityLabel("Remove data for \(site.site)")
        }
        .frame(minHeight: CrestFormRowMetrics.minimumHeight)
        .contextMenu {
            Button("Remove", systemImage: "trash", role: .destructive, action: remove)
        }
    }

    /// What the site keeps, as a list a person reads.
    private var kinds: String {
        site.kinds.map { String(localized: $0.title) }.formatted(.list(type: .and))
    }
}
