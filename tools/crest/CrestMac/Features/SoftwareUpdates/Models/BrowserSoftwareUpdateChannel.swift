import Foundation

/// The release lines Crest can follow, each with the feed and Sparkle channels
/// that carry it.
///
/// `name` is persisted: the chosen channel and the packaged default
/// (`CrestDefaultUpdateChannel`) are stored by it.
struct BrowserSoftwareUpdateChannel: Hashable, Identifiable, Sendable {
    // MARK: - Static Variables

    static let stable = BrowserSoftwareUpdateChannel(
        name: "stable", title: "Stable", guidance: "Recommended for everyday use.", allowedSparkleChannels: [])
    static let nightly = BrowserSoftwareUpdateChannel(
        name: "nightly", title: "Nightly", guidance: "Daily builds. May be less reliable.",
        allowedSparkleChannels: ["nightly"])
    static let development = BrowserSoftwareUpdateChannel(
        name: "development", title: "Development", guidance: "Updates several times a day.",
        allowedSparkleChannels: ["development"], appcastName: "appcast-development")
    static let experimental = BrowserSoftwareUpdateChannel(
        name: "experimental", title: "Experimental", guidance: "Work in testing before it reaches Development.",
        allowedSparkleChannels: ["experimental"], appcastName: "appcast-experimental", isOfferedOnlyWhenBundled: true)

    /// Every channel, in the order the picker lists them.
    static let all: [BrowserSoftwareUpdateChannel] = [stable, nightly, development, experimental]

    /// The channels this build offers. A channel offered only when bundled
    /// appears only in a build packaged for it, so once the branch it serves
    /// reaches Development, normal builds do not show an obsolete choice.
    static var offered: [BrowserSoftwareUpdateChannel] {
        let bundledDefault = Bundle.main.object(forInfoDictionaryKey: "CrestDefaultUpdateChannel") as? String
        return all.filter { !$0.isOfferedOnlyWhenBundled || $0.name == bundledDefault }
    }

    // MARK: - Variables

    let name: String
    let title: LocalizedStringResource
    let guidance: LocalizedStringResource

    /// The Sparkle channels whose items this channel accepts, beyond the
    /// default channel every item without one belongs to.
    let allowedSparkleChannels: Set<String>

    /// The feed this channel has of its own, before the engine's suffix, or
    /// `nil` where the product's main feed carries it.
    let appcastName: String?

    /// Whether only a build packaged for this channel offers it.
    let isOfferedOnlyWhenBundled: Bool

    var id: String { name }

    var customFeedURL: URL? {
        feedURL(for: BrowserEngineRegistration.current.implementationId.family)
    }

    // MARK: - Initializers

    private init(
        name: String, title: LocalizedStringResource, guidance: LocalizedStringResource,
        allowedSparkleChannels: Set<String>, appcastName: String? = nil, isOfferedOnlyWhenBundled: Bool = false
    ) {
        self.name = name
        self.title = title
        self.guidance = guidance
        self.allowedSparkleChannels = allowedSparkleChannels
        self.appcastName = appcastName
        self.isOfferedOnlyWhenBundled = isOfferedOnlyWhenBundled
    }

    // MARK: - Actions - Lookup

    static func named(_ name: String) -> BrowserSoftwareUpdateChannel? {
        all.first { $0.name == name }
    }

    /// Feeds follow the installed product composition. A WebKit preference
    /// inside the Chromium product keeps updating that same dual-engine app.
    func feedURL(for engine: BrowserEngineImplementation.Family) -> URL? {
        guard let filename = appcastName.map({ $0 + engine.appcastSuffix }) ?? engine.mainAppcastName else {
            return nil
        }
        return URL(string: "https://raw.githubusercontent.com/pauljoda/Crest/updates/\(filename).xml")
    }

    // MARK: - Actions - Identity

    static func == (lhs: BrowserSoftwareUpdateChannel, rhs: BrowserSoftwareUpdateChannel) -> Bool {
        lhs.name == rhs.name
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }
}
