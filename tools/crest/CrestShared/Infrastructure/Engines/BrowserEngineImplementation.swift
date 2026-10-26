import Foundation

/// The engine build an adapter wraps. The raw values are the descriptor's
/// `implementationId` and the token namespace staged navigations carry.
enum BrowserEngineImplementation: String, Codable, Sendable {
    case webKitMacOS = "crest.webkit.macos"
    case webKitIOS = "crest.webkit.ios"
    case chromiumMacOS = "crest.chromium.macos"

    // MARK: - Types

    /// The engine an identity, download or saved page state belongs to.
    struct Family: Codable, Hashable, Identifiable, Sendable {
        // MARK: - Static Variables

        static let webKit = Family(
            name: "webkit", appcastSuffix: "-webkit", mainAppcastName: "appcast-webkit",
            restoresHistoryFromOtherVersions: false)
        static let chromium = Family(
            name: "chromium", appcastSuffix: "", mainAppcastName: nil, restoresHistoryFromOtherVersions: true)

        /// Every engine family.
        static let all: [Family] = [webKit, chromium]

        // MARK: - Variables

        /// The engine tag persisted interaction state carries.
        let name: String

        /// What the product built on this engine adds to the name of a
        /// channel's own update feed.
        let appcastSuffix: String

        /// The product's own feed for the channels without one, or `nil` where
        /// the feed bundled in the app serves them.
        let mainAppcastName: String?

        /// True when the engine reads back page history another version of it
        /// saved, as Chromium's session restore does across updates. WebKit
        /// promises to read back only what its own build wrote.
        let restoresHistoryFromOtherVersions: Bool

        var id: String { name }

        // MARK: - Initializers

        private init(
            name: String, appcastSuffix: String, mainAppcastName: String?, restoresHistoryFromOtherVersions: Bool
        ) {
            self.name = name
            self.appcastSuffix = appcastSuffix
            self.mainAppcastName = mainAppcastName
            self.restoresHistoryFromOtherVersions = restoresHistoryFromOtherVersions
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            let name = try container.decode(String.self)
            guard let family = Self.all.first(where: { $0.name == name }) else {
                throw DecodingError.dataCorruptedError(
                    in: container, debugDescription: "Unknown engine family \(name)")
            }
            self = family
        }

        // MARK: - Actions - Coding

        func encode(to encoder: any Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(name)
        }

        // MARK: - Actions - Identity

        static func == (lhs: Family, rhs: Family) -> Bool {
            lhs.name == rhs.name
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(name)
        }
    }

    // MARK: - Variables

    var family: Family {
        switch self {
        case .webKitMacOS, .webKitIOS: .webKit
        case .chromiumMacOS: .chromium
        }
    }
}
