import Foundation

struct BrowsingProfile: Codable, Equatable, Identifiable, Sendable {
    let id: UUID

    init(id: UUID = UUID()) {
        self.id = id
    }
}
