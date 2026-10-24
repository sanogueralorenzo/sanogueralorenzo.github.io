import Foundation

/// A tab or folder a window's sidebar can select.
enum BrowserSelectionItemID: Codable, Hashable, Sendable {
    case tab(UUID)
    case folder(UUID)

    var tabID: UUID? {
        if case .tab(let id) = self { return id }
        return nil
    }
    var folderID: UUID? {
        if case .folder(let id) = self { return id }
        return nil
    }
}
