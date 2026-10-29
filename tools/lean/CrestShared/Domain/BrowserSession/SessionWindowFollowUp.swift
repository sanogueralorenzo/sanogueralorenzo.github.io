import Foundation

/// What one accepted session edit chooses for its issuing window.
struct SessionWindowFollowUp {
    struct Departure {
        let window: UUID
        let space: UUID
        let tab: UUID
    }
    private(set) var window: SessionWindow?
    private(set) var spaceID: UUID?
    private var selections: [UUID: UUID?] = [:]
    private(set) var dismissed: [SessionWindow.Place] = []
    private(set) var departed: [Departure] = []
    init(window: SessionWindow?) { self.window = window }
    var tabs: [ShownTab] { selections.map { ShownTab(spaceID: $0.key, tabID: $0.value) } }
    mutating func showSpace(_ id: UUID) { spaceID = id }
    mutating func showTab(_ id: UUID?, in space: UUID) {
        if window?.tab(in: space) == id {
            selections.removeValue(forKey: space)
        } else {
            selections.updateValue(id, forKey: space)
        }
    }
    mutating func dismiss(_ tab: UUID, in space: UUID) { dismissed.append(SessionWindow.Place(space: space, tab: tab)) }
    mutating func depart(_ tab: UUID, in space: UUID, from window: UUID) {
        departed.append(Departure(window: window, space: space, tab: tab))
    }
    mutating func fallback(in space: UUID, dismissing tab: UUID, available: Set<UUID>) -> UUID? {
        guard window?.tab(in: space) == tab else { return nil }
        dismiss(tab, in: space)
        return window?.dismissalFallback(in: space, dismissing: tab, available: available)
    }
}
