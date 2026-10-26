import Foundation

struct BrowserSidebarWidgetKindID: RawRepresentable, Hashable, Sendable {
    let rawValue: String

    static let nowPlaying = Self(rawValue: "crest.now-playing")
    static let softwareUpdate = Self(rawValue: "crest.software-update")
}

struct BrowserSidebarWidgetID: Hashable, Identifiable, Sendable {
    let kindID: BrowserSidebarWidgetKindID
    let instanceID: String

    var id: String { "\(kindID.rawValue):\(instanceID)" }
}

struct BrowserSidebarWidgetPlatform: OptionSet, Hashable, Sendable {
    let rawValue: Int

    static let macOS = Self(rawValue: 1 << 0)
    static let mobile = Self(rawValue: 1 << 1)
    static let all: Self = [.macOS, .mobile]

    #if os(macOS)
        static let current = Self.macOS
    #else
        static let current = Self.mobile
    #endif
}

struct BrowserSidebarWidgetCapabilities: OptionSet, Hashable, Sendable {
    let rawValue: Int

    /// The shell has a sidebar that remains beside web content.
    static let persistentSidebar = Self(rawValue: 1 << 0)
    /// Standard page Media Session state can be observed and controlled.
    static let mediaSessions = Self(rawValue: 1 << 1)
    /// This build is distributed directly and owns a Sparkle updater.
    static let directSoftwareUpdates = Self(rawValue: 1 << 2)
}

struct BrowserSidebarWidgetRegistration: Equatable, Identifiable, Sendable {
    let id: BrowserSidebarWidgetKindID
    let settingsTitle: String
    let order: Int
    let platforms: BrowserSidebarWidgetPlatform
    let requiredCapabilities: BrowserSidebarWidgetCapabilities
    let instanceLimit: BrowserSidebarWidgetInstanceLimit
    let visibility: BrowserSidebarWidgetVisibility
    let backgroundActivityID: String?
}

extension BrowserSidebarWidgetRegistration {
    static let nowPlaying = Self(
        id: .nowPlaying,
        settingsTitle: String(localized: "Now Playing"),
        order: 200,
        platforms: .all,
        requiredCapabilities: [.mediaSessions],
        instanceLimit: .multiple,
        visibility: .userControllable,
        backgroundActivityID: "crest.media-session-observation"
    )

    static let softwareUpdate = Self(
        id: .softwareUpdate,
        settingsTitle: String(localized: "Software Update"),
        order: 100,
        platforms: .macOS,
        requiredCapabilities: [.directSoftwareUpdates],
        instanceLimit: .single,
        visibility: .mandatory,
        backgroundActivityID: "crest.software-update-observation"
    )
}

/// Who authored a widget. Sources still tag what they publish, but the deck is a
/// single global layer: visibility never consults the scope, so a tab playing
/// media in one profile stays on the card stack in every Space of every profile.
enum BrowserSidebarWidgetScope: Equatable, Sendable {
    case application
    case profile(UUID)
}

enum BrowserMediaSessionPlaybackState: String, Encodable, Equatable, Sendable {
    case none
    case paused
    case playing
}

struct BrowserMediaSessionID: Hashable, Identifiable, Sendable {
    let tabID: UUID
    let documentIdentifier: String

    var id: String {
        "\(tabID.uuidString.lowercased()):\(documentIdentifier)"
    }
}

struct BrowserMediaSessionSnapshot: Equatable, Identifiable, Sendable {
    let id: BrowserMediaSessionID
    let owner: BrowserTabRuntimeAssignment
    /// The owning tab's Crest-visible name, including a reader-supplied custom
    /// title. This is intentionally independent of page playback metadata.
    let ownerTitle: String?
    let title: String?
    let artist: String?
    let album: String?
    let artworkData: Data?
    let playbackState: BrowserMediaSessionPlaybackState
    let isAudible: Bool
    /// Every media element the page has surfaced is muted. Distinct from
    /// `isAudible`, which also goes false for paused or zero-volume playback.
    let isMuted: Bool
    let availableActions: Set<MediaSessionAction>
    let orderingOrdinal: UInt64

    var ownerDisplayTitle: String { ownerTitle ?? "Media tab" }

    var mediaDisplayTitle: String { title ?? "Media from this tab" }

    /// System Now Playing still needs a single primary title. Prefer the
    /// standards-provided media title, with the stable tab title as its fallback.
    var displayTitle: String { title ?? ownerTitle ?? "Untitled media" }

    var secondaryMetadata: String? {
        [artist, album]
            .compactMap { value in
                guard let value, !value.isEmpty else { return nil }
                return value
            }
            .joined(separator: " · ")
            .nilIfEmpty
    }
}

struct BrowserSoftwareUpdateWidgetSnapshot: Equatable, Sendable {
    let phase: BrowserSoftwareUpdatePhase
    let title: String
    let version: String?
    let build: String?
    let releaseNotes: String?
    let informationURL: URL?
    let message: String?
    let progress: Double?
    let isInformationOnly: Bool
    let allowsInstallation: Bool
    let allowsSkipping: Bool
    let allowsCancellation: Bool
    let allowsInstallAndRelaunch: Bool
    let allowsInstallationRetry: Bool
    let isFixture: Bool
}

struct BrowserSidebarWidgetInstance: Equatable, Identifiable, Sendable {
    let id: BrowserSidebarWidgetID
    let scope: BrowserSidebarWidgetScope
    let orderingOrdinal: UInt64
    let presentation: BrowserSidebarWidgetPresentation
    let availableActions: Set<BrowserSidebarWidgetAction>
}
