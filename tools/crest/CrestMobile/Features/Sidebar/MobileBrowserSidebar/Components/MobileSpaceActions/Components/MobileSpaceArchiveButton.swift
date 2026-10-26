import SwiftUI

struct MobileSpaceArchiveButton: View {
    let utilityPresentationStyle: MobileBrowserSidebarUtilityPresentationStyle
    let archivedTabCount: Int
    let commonListsAreExpanded: Bool
    let downloads: [DownloadState]
    let newDownloads: [DownloadState]
    let badgeColor: Color
    let showArchive: () -> Void
    let toggleCommonLists: () -> Void
    let recordCommonListsTriggerFrame: (CGRect) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: presentsInline ? toggleCommonLists : showArchive) {
            MobileSpaceUtilityButtonLabel(systemImage: "archivebox")
        }
        .symbolVariant(
            presentsInline && commonListsAreExpanded ? .fill : .none
        )
        .foregroundStyle(.primary)
        .symbolEffect(
            .bounce,
            value: reduceMotion ? nil : inlineNotificationID
        )
        .modifier(
            MobileSpaceUtilityBadge(
                count: presentsInline ? newDownloads.count : 0,
                tint: downloads.contains(where: { $0.phase.needsAttention })
                    ? .red
                    : badgeColor,
                progress: downloads.notificationProgress
            )
        )
        .accessibilityLabel(
            presentsInline ? "Archive, History, and Downloads" : "Archive"
        )
        .accessibilityValue(accessibilityValue)
        .accessibilityIdentifier(
            presentsInline ? "common-lists-button" : "archive-button"
        )
        .onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .global)
        } action: { frame in
            recordCommonListsTriggerFrame(frame)
        }
    }

    /// Where the lists come up inline, this control is the switcher for all
    /// three of them; where they come up as sheets, it opens the archive alone
    /// and downloads get a control of their own beside it.
    private var presentsInline: Bool {
        utilityPresentationStyle == .inline
    }

    private var accessibilityValue: String {
        if presentsInline {
            let state = commonListsAreExpanded ? "Expanded" : "Collapsed"
            guard !newDownloads.isEmpty else { return state }
            return "\(state), \(newDownloads.count) new downloads"
        }
        return BrowserChromeAccessibility.countValue(
            archivedTabCount,
            singular: "archived tab",
            plural: "archived tabs"
        )
    }

    private var inlineNotificationID: UUID? {
        presentsInline ? newDownloads.first?.id : nil
    }
}
