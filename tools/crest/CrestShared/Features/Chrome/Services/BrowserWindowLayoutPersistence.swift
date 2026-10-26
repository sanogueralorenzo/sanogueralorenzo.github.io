import CoreGraphics
import Foundation

@MainActor
struct BrowserWindowLayoutPersistence {
    let windowState: BrowserWindowStateStore?

    func restoreSidebarWidth(_ width: CGFloat, transaction: inout BrowserSidebarWidthTransaction) {
        guard windowState == nil, width != transaction.persistedWidth else { return }
        transaction.restore(persistedWidth: width)
    }

    /// Returns a fallback preference only when no per-window store is available.
    func commitSidebarWidth(_ width: CGFloat, transaction: inout BrowserSidebarWidthTransaction) -> CGFloat? {
        transaction.resize(to: width)
        guard let committedWidth = transaction.commit() else { return nil }
        guard let windowState else { return committedWidth }
        windowState.captureSidebar(width: Double(committedWidth))
        return nil
    }

    func seedSplitLayout(
        groupID: UUID?, memberCount: Int, transaction: inout BrowserSplitWidthTransaction
    ) {
        guard memberCount > 0 else { return }
        let persisted = groupID.flatMap { windowState?.splitColumnFractions(for: $0) }
        transaction.begin(
            fractions: BrowserSplitColumnLayout.seedFractions(persisted: persisted, memberCount: memberCount)
        )
    }

    func commitSplitLayout(_ fractions: [Double], groupID: UUID?) {
        guard let windowState, let groupID else { return }
        windowState.captureSplitLayout(fractions: fractions, for: groupID)
    }
}
