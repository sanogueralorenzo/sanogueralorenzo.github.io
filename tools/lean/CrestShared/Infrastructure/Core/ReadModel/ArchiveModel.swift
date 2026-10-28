import Foundation
import Observation

/// A Space's archived tabs, in order. It is an object of its own so that
/// archiving notifies the archive's readers and never the sidebar's. Its
/// entries are stored before they are announced; see
/// `BrowserStoreFirstObservable`.
@MainActor
@Observable
final class ArchiveModel {
    // MARK: - Variables

    private(set) var entries: [ArchivedTabState] {
        get { observed(\.entriesStorage, as: \.entries) }
        set { publish(newValue, into: \.entriesStorage, as: \.entries) }
    }
    @ObservationIgnored private var entriesStorage: [ArchivedTabState]

    // MARK: - Initializers

    init(_ entries: [ArchivedTabState]) {
        entriesStorage = entries
    }

    // MARK: - Actions - Reading

    func contains(tabID: UUID) -> Bool {
        entries.contains { $0.tab.id == tabID }
    }

    // MARK: - Actions - Changes

    /// The tabs `removed` names are gone. Each `archived` entry replaces the
    /// entry for its tab where that entry stands, or goes after the others
    /// when it is new. `order`, when present, names every archived tab in its
    /// new order.
    func apply(_ change: ArchiveChanged) {
        let gone = Set(change.removed)
        var next = gone.isEmpty ? entriesStorage : entriesStorage.filter { !gone.contains($0.tab.id) }
        for entry in change.archived {
            if let index = next.firstIndex(where: { $0.tab.id == entry.tab.id }) {
                next[index] = entry
            } else {
                next.append(entry)
            }
        }
        if let order = change.order {
            let byID = Dictionary(next.map { ($0.tab.id, $0) }, uniquingKeysWith: { first, _ in first })
            next = order.compactMap { byID[$0] }
        }
        replace(with: next)
    }

    func replace(with entries: [ArchivedTabState]) {
        self.entries = entries
    }
}

extension ArchiveModel: BrowserStoreFirstObservable {}
