import SwiftUI

struct MobileSpaceDownloadsButton: View {
    let downloads: [DownloadState]
    let newDownloads: [DownloadState]
    let badgeColor: Color
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            MobileSpaceUtilityButtonLabel(systemImage: symbol)
        }
        .foregroundStyle(.primary)
        .symbolEffect(.bounce, value: reduceMotion ? nil : newDownloads.first?.id)
        .modifier(
            MobileSpaceUtilityBadge(
                count: newDownloads.count,
                tint: badgeColor,
                progress: downloads.notificationProgress
            )
        )
        .accessibilityLabel("Downloads")
        .accessibilityValue(
            BrowserChromeAccessibility.countValue(
                downloads.count,
                singular: "download",
                plural: "downloads"
            )
        )
        .accessibilityIdentifier("downloads-button")
    }

    private var symbol: String {
        if downloads.contains(where: { $0.phase.needsAttention }) {
            return "exclamationmark.arrow.trianglehead.2.clockwise.rotate.90"
        }
        if downloads.contains(where: { $0.phase.isLive }) {
            return "arrow.down.circle"
        }
        return "arrow.down.circle.fill"
    }
}

#if DEBUG
    #Preview("Component") {
        MobileSpaceDownloadsButton(
            downloads: [BrowserUtilityListPreviewFixture.activeDownload],
            newDownloads: [BrowserUtilityListPreviewFixture.finishedDownload], badgeColor: .indigo, action: {}
        ).padding()
    }
#endif
