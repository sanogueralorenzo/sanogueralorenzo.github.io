import Foundation

/// What the window's multi-selection holds once a tab batch is done. Each
/// reselection selects its own items, given the copies the action made and
/// the selection it acted on.
struct BrowserTabReselection: Sendable {
    // MARK: - Static Variables

    /// Nothing: the selected tabs left the window's list.
    static let cleared = BrowserTabReselection { selection, _, _ in
        selection.clear()
    }

    /// The copies the action made.
    static let copies = BrowserTabReselection { selection, copies, _ in
        selection.selectAll(units: copies.map { [.tab($0.copyTabID)] })
    }

    /// The same items, a copy standing in for each source the action copied.
    static let items = BrowserTabReselection { selection, copies, request in
        let copied = Dictionary(uniqueKeysWithValues: copies.map { ($0.sourceTabID, $0.copyTabID) })
        selection.selectAll(
            units: request.rootItems.map { item in
                guard case .tab(let id) = item, let copy = copied[id] else { return [item] }
                return [.tab(copy)]
            })
    }

    // MARK: - Variables

    /// Selects what the action leaves selected in the window's `selection`.
    let apply:
        @MainActor @Sendable (
            _ selection: BrowserTabMultiSelection, _ copies: [TabCopied], _ request: BrowserCapturedSelection
        ) -> Void

    // MARK: - Initializers

    private init(
        apply: @escaping @MainActor @Sendable (BrowserTabMultiSelection, [TabCopied], BrowserCapturedSelection) -> Void
    ) {
        self.apply = apply
    }
}
