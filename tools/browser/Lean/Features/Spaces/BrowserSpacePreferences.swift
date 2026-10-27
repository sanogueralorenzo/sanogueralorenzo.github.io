import Foundation

struct BrowserSpacePreferences: Codable, Equatable {
    var blocksContent = true
    var historyRetention = BrowserDataRetention.forever
    var archiveRetention = BrowserDataRetention.forever
    var downloadRetention = BrowserDataRetention.forever
}

extension BrowserStore {
    func spacePreferences(_ id: UUID) -> BrowserSpacePreferences {
        session.spaces.first { $0.id == id }?.browsingPreferences
            ?? BrowserSpacePreferences(blocksContent: preferences.blocksContent)
    }

    func updateSpacePreferences(_ id: UUID, _ update: (inout BrowserSpacePreferences) -> Void) {
        guard let index = session.spaces.firstIndex(where: { $0.id == id }) else { return }
        let previous = spacePreferences(id)
        var value = previous
        update(&value)
        session.spaces[index].browsingPreferences = value
        if previous.blocksContent != value.blocksContent {
            reloadContentBlocking(in: id)
        }
        owner.sweepExpiredRecords(force: true)
        changed()
    }

}
