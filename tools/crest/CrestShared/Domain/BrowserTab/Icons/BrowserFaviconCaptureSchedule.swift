import Foundation

/// When a favicon session tries the page's document again after the first
/// capture and the fallback both come back empty.
struct BrowserFaviconCaptureSchedule: Sendable {
    // MARK: - Static Variables

    static let immediate = Self(retryDelays: [])
    static let delayedDocumentIcons = Self(retryDelays: [.milliseconds(500), .seconds(2)])

    // MARK: - Variables

    let retryDelays: [Duration]
}
