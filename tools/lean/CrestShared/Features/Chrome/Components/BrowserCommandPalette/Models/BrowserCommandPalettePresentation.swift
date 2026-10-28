import Foundation

enum BrowserCommandPalettePresentation: Equatable, Sendable {
    case overlay
    case embedded
}

/// What a palette is opened for. A palette opened again for other values
/// starts over, so a stale query never survives into another tab or Space.
struct BrowserCommandPalettePresentationIdentity: Hashable {
    // MARK: - Variables

    let mode: BrowserCommandPaletteMode?
    let focusRequest: Int?
    let source: BrowserTabRuntimeAssignment?
    let spaceAssignment: BrowserSpaceRuntimeAssignment?

    // MARK: - Initializers

    @MainActor
    init(mode: BrowserCommandPaletteMode, space: SpaceModel?, source: BrowserTabRuntimeAssignment?) {
        self.mode = mode
        focusRequest = nil
        self.source = source
        spaceAssignment = space.map { BrowserSpaceRuntimeAssignment(spaceID: $0.id, profileID: $0.profileID) }
    }

    @MainActor
    init(focusRequest: Int? = nil, space: SpaceModel?, source: BrowserTabRuntimeAssignment?) {
        mode = nil
        self.focusRequest = focusRequest
        self.source = source
        spaceAssignment = space.map { BrowserSpaceRuntimeAssignment(spaceID: $0.id, profileID: $0.profileID) }
    }
}
