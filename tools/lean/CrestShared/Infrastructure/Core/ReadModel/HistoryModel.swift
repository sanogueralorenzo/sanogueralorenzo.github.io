import Foundation
import Observation

/// A Space's history, newest first. It is an object of its own so that a
/// visit notifies the history's readers and never the sidebar's. Its entries
/// are stored before they are announced; see `BrowserStoreFirstObservable`.
@MainActor
@Observable
final class HistoryModel {
    // MARK: - Variables

    private(set) var entries: [HistoryEntryState] {
        get { observed(\.entriesStorage, as: \.entries) }
        set { publish(newValue, into: \.entriesStorage, as: \.entries) }
    }
    @ObservationIgnored private var entriesStorage: [HistoryEntryState]

    // MARK: - Initializers

    init(_ entries: [HistoryEntryState]) {
        entriesStorage = entries
    }

    // MARK: - Actions - Changes

    /// The `removed` entries are gone, and the `recorded` entries, newest
    /// first, replace the entries with their identities and go before every
    /// other. `order`, when present, names every entry in its new order.
    func apply(_ change: HistoryChanged) {
        guard !change.recorded.isEmpty || !change.removed.isEmpty || change.order != nil else { return }
        let gone = Set(change.removed).union(change.recorded.map(\.id))
        var next = change.recorded + entriesStorage.filter { !gone.contains($0.id) }
        if let order = change.order {
            let byID = Dictionary(next.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            next = order.compactMap { byID[$0] }
        }
        replace(with: next)
    }

    func replace(with entries: [HistoryEntryState]) {
        self.entries = entries
    }
}

extension HistoryModel: BrowserStoreFirstObservable {}
