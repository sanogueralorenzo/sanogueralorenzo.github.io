import Foundation

@MainActor
struct BrowserSpaceOrderActions {
    let browser: BrowserStore
    let spaceID: UUID?

    var canMoveUp: Bool {
        guard let index else { return false }
        return index > 0
    }

    var canMoveDown: Bool {
        guard let index else { return false }
        return index < browser.spaceModels.count - 1
    }

    func moveUp() {
        guard let index, index > 0 else { return }
        browser.moveSpaces(from: IndexSet(integer: index), to: index - 1)
    }

    func moveDown() {
        guard let index, index < browser.spaceModels.count - 1 else { return }
        // The insertion offset precedes removal of the source Space.
        browser.moveSpaces(from: IndexSet(integer: index), to: index + 2)
    }

    private var index: Int? {
        guard let spaceID, !browser.isDeleting(spaceID) else { return nil }
        return browser.spaceModels.firstIndex { $0.id == spaceID }
    }
}
