import Foundation
import Observation

/// One list a Space's sidebar shows together, the top level of a section or
/// the inside of a folder, observed on its own: a move redraws only the list
/// it moves within, and a new title or address redraws no list. Its rows are
/// stored before they are announced; see `BrowserStoreFirstObservable`.
@MainActor
@Observable
final class SidebarListModel {
    // MARK: - Variables

    /// The rows in order. A collapsed folder's list still holds its rows.
    var rows: [SidebarRow] { observed(\.rowsStorage, as: \.rows) }
    @ObservationIgnored private var rowsStorage: [SidebarRow]
    /// Whether the list holds no row, observed apart from the rows, so a view
    /// that asks only this hears nothing of a move.
    var isEmpty: Bool { observed(\.isEmptyStorage, as: \.isEmpty) }
    @ObservationIgnored private var isEmptyStorage: Bool
    /// Whether the list holds a tab or a split row and not only folders,
    /// observed apart from the rows.
    var holdsTabRows: Bool { observed(\.holdsTabRowsStorage, as: \.holdsTabRows) }
    @ObservationIgnored private var holdsTabRowsStorage: Bool

    // MARK: - Initializers

    init(rows: [SidebarRow] = []) {
        rowsStorage = rows
        isEmptyStorage = rows.isEmpty
        holdsTabRowsStorage = Self.holdsTabRows(rows)
    }

    // MARK: - Actions - Changes

    /// Takes the list's rows again, announcing them only when they differ,
    /// and whether the list is empty or holds tab rows only when that
    /// changes. Every value is stored before any is announced.
    func update(_ rows: [SidebarRow]) {
        guard rowsStorage != rows else { return }
        let isEmpty = rows.isEmpty
        let holdsTabRows = Self.holdsTabRows(rows)
        let emptinessChanged = isEmptyStorage != isEmpty
        let tabRowsChanged = holdsTabRowsStorage != holdsTabRows
        rowsStorage = rows
        isEmptyStorage = isEmpty
        holdsTabRowsStorage = holdsTabRows
        withMutation(keyPath: \.rows) {}
        if emptinessChanged { withMutation(keyPath: \.isEmpty) {} }
        if tabRowsChanged { withMutation(keyPath: \.holdsTabRows) {} }
    }

    private static func holdsTabRows(_ rows: [SidebarRow]) -> Bool {
        rows.contains { !$0.kind.opensList }
    }
}

extension SidebarListModel: BrowserStoreFirstObservable {}
