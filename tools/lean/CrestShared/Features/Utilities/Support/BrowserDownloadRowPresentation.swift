import Foundation

struct BrowserDownloadRowPresentation: Sendable {
    /// The narrowest row that keeps the status and transfer metrics on one line.
    static let inlineMinimumWidth: CGFloat = 360

    let bytesReceived: Int64
    let totalBytes: Int64?
    let progress: Double
    let bytesPerSecond: Double?
    let estimatedTimeRemaining: TimeInterval?
    let statusText: BrowserUtilityText
    let statusNeedsAttention: Bool
    let showsTransferMetrics: Bool
    let showsStatusAlongsideMetrics: Bool

    static func resolve(
        item: DownloadState
    ) -> BrowserDownloadRowPresentation {
        let telemetry = item.telemetry
        let isActivelyDownloading =
            item.phase.isTransferring
            && !telemetry.isPaused
        let statusText: BrowserUtilityText =
            item.phase.isTransferring && telemetry.isPaused
            ? .localized("Paused")
            : status(of: item)
        let showsTransferMetrics =
            telemetry.bytesReceived > 0
            || telemetry.totalBytes != nil
            || item.phase.isComplete
        return BrowserDownloadRowPresentation(
            bytesReceived: telemetry.bytesReceived,
            totalBytes: telemetry.totalBytes,
            progress: item.progress,
            bytesPerSecond: isActivelyDownloading
                ? telemetry.bytesPerSecond
                : nil,
            estimatedTimeRemaining: isActivelyDownloading
                ? telemetry.estimatedTimeRemaining
                : nil,
            statusText: statusText,
            statusNeedsAttention: item.phase.needsAttention,
            showsTransferMetrics: showsTransferMetrics,
            showsStatusAlongsideMetrics: showsTransferMetrics
                && !isActivelyDownloading
        )
    }

    /// The phase's title, or for a phase without one, why the record stopped
    /// in its localized words, else its own message. Search matches it
    /// without waiting for transfer telemetry.
    static func status(of item: DownloadState) -> BrowserUtilityText {
        if let title = item.phase.title { return .localized(title) }
        if let failure = item.failure { return .localized(failure.message) }
        return .verbatim(item.message ?? "")
    }

    var hasSecondaryTransferMetrics: Bool {
        bytesPerSecond != nil
            || estimatedTimeRemaining != nil
            || showsStatusAlongsideMetrics
    }

    /// How a row this wide lays the presentation out.
    func layout(
        availableWidth: CGFloat,
        usesAccessibilityTextSize: Bool
    ) -> BrowserDownloadRowLayout {
        // Without metrics the status is the only line; a second would repeat it.
        guard hasSecondaryTransferMetrics else {
            return .singleLine
        }
        guard !usesAccessibilityTextSize,
            !statusNeedsAttention,
            availableWidth >= Self.inlineMinimumWidth
        else {
            return .stacked
        }
        return .inline
    }
}

enum BrowserDownloadRowLayout: Equatable, Sendable {
    case singleLine
    case inline
    case stacked
}
