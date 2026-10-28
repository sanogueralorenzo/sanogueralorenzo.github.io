import Foundation

/// The stable feed for the installed product's engine composition. The
/// dual-engine product reads its feed from Info.plist; WebKit uses its own.
struct BrowserSoftwareUpdateFeed {
    // MARK: - Static Variables

    static let current = BrowserSoftwareUpdateFeed(for: BrowserEngineRegistration.current.implementationId.family)

    // MARK: - Variables

    let url: URL?

    // MARK: - Initializers

    init(for engine: BrowserEngineImplementation.Family) {
        url = engine.mainAppcastName.flatMap {
            URL(string: "https://raw.githubusercontent.com/pauljoda/Crest/updates/\($0).xml")
        }
    }
}
