import Foundation

enum MediaSessionAction: Int, CaseIterable, Sendable {
    case play
    case pause
    case previousTrack
    case nextTrack
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
    // MARK: - Variables

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

    /// Prefer the standards-provided media title, with the tab title as its fallback.
    var displayTitle: String { title ?? ownerTitle ?? "Untitled media" }
}
