import Foundation

/// What a sidebar card shows: the kind of widget and the state it draws.
enum BrowserSidebarWidgetPresentation: Equatable, Sendable {
    case nowPlaying(BrowserMediaSessionSnapshot)
    case softwareUpdate(BrowserSoftwareUpdateWidgetSnapshot)

    // MARK: - Variables

    /// The card as the deck's page indicator names it to assistive
    /// technologies, after its position.
    var deckDescription: String {
        switch self {
        case .nowPlaying(let session): "Now Playing, \(session.ownerDisplayTitle)"
        case .softwareUpdate: "Update Available"
        }
    }
}
