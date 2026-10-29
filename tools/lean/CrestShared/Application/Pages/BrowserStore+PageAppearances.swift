import Foundation

extension BrowserStore {
    var pageAppearances: [TabPageAppearance] {
        core.pages.appearances(workspace: family.workspaceID, window: windowID)
    }
}
