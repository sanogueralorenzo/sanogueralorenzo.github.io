import Foundation

struct BrowserQuickWindowRequest: Hashable, Identifiable, Sendable {
    private static let emptyLookupURL: URL = {
        var components = URLComponents()
        components.scheme = "crest"
        components.host = "quick-window"
        return components.url ?? URL(fileURLWithPath: "/")
    }()

    let id: UUID
    var url: URL
    let spaceAssignment: BrowserSpaceRuntimeAssignment
    let targetWindowID: UUID?
    let sourcePresentation: BrowserPeekSourcePresentation?
    /// The page the core already opened for the window, a popup window a
    /// page asked for, which its target window hosts until the Quick Window
    /// takes it. A window a relaunch restores has none and loads `url`.
    let openedPageID: UUID?

    var spaceID: UUID { spaceAssignment.spaceID }

    var assignment: BrowserSpaceRuntimeAssignment {
        spaceAssignment
    }

    init(
        id: UUID = UUID(),
        url: URL,
        spaceAssignment: BrowserSpaceRuntimeAssignment,
        targetWindowID: UUID? = nil,
        sourcePresentation: BrowserPeekSourcePresentation? = nil,
        openedPageID: UUID? = nil
    ) {
        self.id = id
        self.url = url
        self.spaceAssignment = spaceAssignment
        self.targetWindowID = targetWindowID
        self.sourcePresentation = sourcePresentation
        self.openedPageID = openedPageID
    }

    static func empty(
        id: UUID = UUID(),
        spaceAssignment: BrowserSpaceRuntimeAssignment,
        targetWindowID: UUID? = nil
    ) -> BrowserQuickWindowRequest {
        BrowserQuickWindowRequest(
            id: id,
            url: emptyLookupURL,
            spaceAssignment: spaceAssignment,
            targetWindowID: targetWindowID
        )
    }

    var initialURL: URL? {
        url == Self.emptyLookupURL ? nil : url
    }

    /// Two requests for the same address in the same Space ask for the same
    /// window, except a popup window's: every window a page asks for is one
    /// of its own.
    static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.openedPageID == nil, rhs.openedPageID == nil else { return lhs.id == rhs.id }
        return switch (lhs.initialURL, rhs.initialURL) {
        case (.some(let lhsURL), .some(let rhsURL)):
            lhs.assignment == rhs.assignment && lhsURL == rhsURL
        case (.none, .none):
            lhs.id == rhs.id
        default:
            false
        }
    }

    func hash(into hasher: inout Hasher) {
        if openedPageID == nil, let initialURL {
            hasher.combine(assignment)
            hasher.combine(initialURL)
        } else {
            hasher.combine(id)
        }
    }
}
