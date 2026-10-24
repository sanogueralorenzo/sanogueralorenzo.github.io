import SwiftUI

/// The switcher's page-side accessory: one control for the archive, history,
/// and downloads lists, badged when downloads have finished unseen.
struct BrowserSpaceSwitcherCommonListsButton: View {
    let isExpanded: Bool
    let downloads: [DownloadState]
    let newDownloads: [DownloadState]
    let badgeColor: Color
    let action: () -> Void
    let recordFrame: (CGRect) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    #if os(macOS)
        @Environment(BrowserMacDownloadFeedbackState.self) private var downloadFeedback:
            BrowserMacDownloadFeedbackState?
    #endif

    var body: some View {
        Button("Common Lists", systemImage: "archivebox", action: action)
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .frame(
                width: BrowserSpaceSwitcherLayout.utilityButtonSize,
                height: BrowserSpaceSwitcherLayout.utilityButtonSize
            )
            .symbolVariant(isExpanded ? .fill : .none)
            .symbolEffect(
                .bounce,
                value: reduceMotion ? nil : arrivalTrigger
            )
            .overlay(alignment: .topTrailing) {
                if !newDownloads.isEmpty {
                    BrowserUtilityNotificationBadge(
                        count: newDownloads.count,
                        tint: downloads.contains(where: { $0.phase.needsAttention })
                            ? .red
                            : badgeColor,
                        progress: downloads.notificationProgress
                    )
                    .offset(
                        x: BrowserUtilitySwitcherLayout.notificationBadgeOffset,
                        y: -BrowserUtilitySwitcherLayout.notificationBadgeOffset
                    )
                }
            }
            .zIndex(newDownloads.isEmpty ? 0 : 1)
            .help("Archive, History, and Downloads")
            .accessibilityValue(accessibilityValue)
            .accessibilityIdentifier("common-lists-button")
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .global)
            } action: { frame in
                recordFrame(frame)
            }
    }

    private var accessibilityValue: String {
        let state = isExpanded ? "Expanded" : "Collapsed"
        guard !newDownloads.isEmpty else { return state }
        return "\(state), \(newDownloads.count) new downloads"
    }

    private enum ArrivalTrigger: Equatable {
        case flight(Int)
        case download(UUID?)
    }

    private var arrivalTrigger: ArrivalTrigger {
        #if os(macOS)
            if let downloadFeedback { return .flight(downloadFeedback.arrivalCount) }
        #endif
        return .download(newDownloads.first?.id)
    }
}

#if DEBUG
    #Preview("Download badge and expansion") {
        @Previewable @State var expanded = false
        BrowserSpaceSwitcherCommonListsButton(
            isExpanded: expanded, downloads: [BrowserUtilityListPreviewFixture.activeDownload],
            newDownloads: [BrowserUtilityListPreviewFixture.finishedDownload], badgeColor: .indigo,
            action: { expanded.toggle() }, recordFrame: { _ in }
        ).padding()
    }
#endif
