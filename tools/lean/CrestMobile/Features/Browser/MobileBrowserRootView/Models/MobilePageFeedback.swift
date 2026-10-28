import Foundation

/// What the page's feedback capsule says: its words, its symbol, and what
/// VoiceOver reads for it.
struct MobilePageFeedback: Equatable {
    // MARK: - Variables

    let label: String
    let systemImage: String
    let accessibilityLabel: String

    // MARK: - Actions - Feedback

    /// The page's zoom, as `label` names it.
    static func pageZoom(_ label: String) -> MobilePageFeedback {
        MobilePageFeedback(
            label: label, systemImage: "textformat.size",
            accessibilityLabel: String(localized: "Page zoom \(label)"))
    }

    /// Clearing one site's `category` ended: cleared by every engine, or not.
    static func siteData(_ category: BrowsingDataCategory, cleared: Bool) -> MobilePageFeedback {
        let label = String(localized: (cleared ? category.clearedTitle : category.failedTitle) ?? category.title)
        return MobilePageFeedback(
            label: label, systemImage: cleared ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
            accessibilityLabel: label)
    }
}
