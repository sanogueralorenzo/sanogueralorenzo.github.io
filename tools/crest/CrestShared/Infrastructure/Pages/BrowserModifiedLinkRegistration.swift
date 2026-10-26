import Foundation

/// The tab a modified link opened, with the Space that owns it, as the read
/// model holds them.
@MainActor
struct BrowserModifiedLinkRegistration {
    let tab: TabStateModel
    let space: SpaceModel
}
