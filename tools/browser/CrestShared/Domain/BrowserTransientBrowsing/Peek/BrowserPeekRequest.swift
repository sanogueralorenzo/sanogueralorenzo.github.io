import Foundation

// MARK: - Types

enum BrowserPeekTrigger: String, Codable, Equatable, Sendable {
    case protectedSavedSite
    case modifierClick
    case linkDrag
    case longPress
    case contextMenu
}

struct BrowserPeekRequest: Identifiable, Equatable, Sendable {
    let id: UUID
    let url: URL
    let sourceTabID: UUID
    let sourceTitle: String
    let spaceAssignment: BrowserSpaceRuntimeAssignment
    let trigger: BrowserPeekTrigger
    let sourcePresentation: BrowserPeekSourcePresentation?
    let engineNavigation: BrowserEngineNavigation?

    var spaceID: UUID { spaceAssignment.spaceID }

    var assignment: BrowserSpaceRuntimeAssignment { spaceAssignment }

    init(
        id: UUID = UUID(),
        url: URL,
        sourceTabID: UUID,
        sourceTitle: String,
        spaceAssignment: BrowserSpaceRuntimeAssignment,
        trigger: BrowserPeekTrigger,
        sourcePresentation: BrowserPeekSourcePresentation? = nil,
        engineNavigation: BrowserEngineNavigation? = nil
    ) {
        self.id = id
        self.url = url
        self.sourceTabID = sourceTabID
        self.sourceTitle = sourceTitle
        self.spaceAssignment = spaceAssignment
        self.trigger = trigger
        self.sourcePresentation = sourcePresentation
        self.engineNavigation = engineNavigation
    }
}
