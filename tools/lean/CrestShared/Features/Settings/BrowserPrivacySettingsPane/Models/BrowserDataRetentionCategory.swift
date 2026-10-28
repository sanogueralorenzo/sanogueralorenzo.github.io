import Foundation

/// The records a Space keeps for a limited time, each with its own retention.
///
/// `name` reaches the automation suites through the picker's accessibility
/// identifier.
struct BrowserDataRetentionCategory: Hashable, Identifiable, Sendable {
    // MARK: - Static Variables

    static let history = BrowserDataRetentionCategory(
        name: "history", title: "History", cleanupDescription: "history entries", retention: \.history)
    static let archive = BrowserDataRetentionCategory(
        name: "archive", title: "Archived Tabs", cleanupDescription: "archived tabs", retention: \.archive)
    static let downloads = BrowserDataRetentionCategory(
        name: "downloads", title: "Download Records", cleanupDescription: "download records",
        retention: \.downloads)

    /// Every category, in the order Settings lists them.
    static let all: [BrowserDataRetentionCategory] = [history, archive, downloads]

    // MARK: - Variables

    let name: String
    let title: LocalizedStringResource

    /// The records the category's cleanup deletes, inside a sentence.
    let cleanupDescription: LocalizedStringResource

    /// The Space preference that holds this category's retention.
    let retention: WritableKeyPath<DataRetentionPreferences, DataRetention> & Sendable

    var id: String { name }

    // MARK: - Initializers

    private init(
        name: String, title: LocalizedStringResource, cleanupDescription: LocalizedStringResource,
        retention: WritableKeyPath<DataRetentionPreferences, DataRetention> & Sendable
    ) {
        self.name = name
        self.title = title
        self.cleanupDescription = cleanupDescription
        self.retention = retention
    }

    // MARK: - Actions - Identity

    static func == (lhs: BrowserDataRetentionCategory, rhs: BrowserDataRetentionCategory) -> Bool {
        lhs.name == rhs.name
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }
}
