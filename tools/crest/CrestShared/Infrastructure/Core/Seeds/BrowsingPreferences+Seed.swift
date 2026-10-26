import Foundation

extension BrowsingPreferences {
    // MARK: - Variables

    static let seeded = BrowsingPreferences.seeded()

    // MARK: - Initializers

    static func seeded(blocking: ContentBlockingPolicy = .balanced) -> BrowsingPreferences {
        BrowsingPreferences(
            contentBlocking: blocking,
            dataRetention: DataRetentionPreferences(history: .forever, archive: .forever, downloads: .forever))
    }
}
