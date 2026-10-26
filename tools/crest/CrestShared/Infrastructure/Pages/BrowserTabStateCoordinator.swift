import Foundation

/// Owns session-state eligibility and pending copies without retaining pages.
/// The platform supplies a page only while capturing its opaque engine state.
@MainActor
final class BrowserTabStateCoordinator {
    private let archive: (any BrowserTabStateArchiving)?
    private var pendingCopies: [BrowserTabRuntimeAssignment: BrowserTabStateEnvelope] = [:]
    private var lastPrunedTabIDsByProfileID: [UUID: Set<UUID>] = [:]

    var archivesResidentPages: Bool { archive != nil }

    init(archive: (any BrowserTabStateArchiving)?) {
        self.archive = archive
    }

    func retainCopies(for tabIDs: Set<UUID>) {
        pendingCopies = pendingCopies.filter { tabIDs.contains($0.key.tabID) }
    }

    func retainCopies(matching assignments: Set<BrowserTabRuntimeAssignment>) {
        pendingCopies = pendingCopies.filter { assignments.contains($0.key) }
    }

    /// Keeps what the copy `assignment` opens with: its engine state, the
    /// core's history, or both. A page with no engine state yet still has the
    /// history the core keeps for it.
    func prepareCopy(_ state: Data?, url: URL?, history: Data?, for assignment: BrowserTabRuntimeAssignment) {
        guard state != nil || history != nil else { return }
        pendingCopies[assignment] = BrowserTabStateEnvelope(
            interactionState: state ?? Data(), url: url, history: history)
    }

    func archivePage(_ page: BrowserPlatformPage, for tabID: UUID) {
        archivePage(page, showing: page.live.documentURL, for: tabID)
    }

    /// Archives the page's state as showing `url`, for a page whose live state
    /// the core no longer holds.
    func archivePage(_ page: BrowserPlatformPage, showing url: URL?, for tabID: UUID) {
        // WebKit drives adopted popups; they are never persisted as user tabs.
        guard let archive, !page.wasOpenedAsPopup else { return }
        // The core keeps the page's history whether or not its engine has
        // state to keep yet, as before its first document commits. Such a
        // page keeps the engine state its archive already holds, so an empty
        // renderer never replaces a useful one.
        let history = page.corePage.archivedHistory
        var state = page.interactionState
        var shown = url
        if state == nil, history != nil,
            let kept = archive.archivedState(profileID: page.profileID, tabID: tabID)
                .flatMap(BrowserTabStateEnvelope.decode),
            kept.isRestorable
        {
            state = kept.interactionState
            shown = kept.url
        }
        guard state != nil || history != nil else { return }
        archive.archive(
            interactionState: state ?? Data(),
            url: shown,
            history: history,
            profileID: page.profileID,
            tabID: tabID
        )
    }

    /// The back and forward history the tab's pending copy or archive keeps,
    /// when it still shows `url`, which the core takes back before the tab's
    /// page opens. Leaves the engine history for the page to restore.
    func history(for assignment: BrowserTabRuntimeAssignment, expecting url: URL) -> Data? {
        envelope(for: assignment, expecting: url, consumePendingCopy: false)?.history
    }

    func interactionState(
        for assignment: BrowserTabRuntimeAssignment,
        expecting url: URL,
        consumePendingCopy: Bool = true
    ) -> Data? {
        guard let envelope = envelope(for: assignment, expecting: url, consumePendingCopy: consumePendingCopy),
            envelope.isRestorable
        else { return nil }
        return envelope.interactionState
    }

    /// What the tab's pending copy keeps, or else its archive, when it still
    /// shows `url`.
    private func envelope(
        for assignment: BrowserTabRuntimeAssignment,
        expecting url: URL,
        consumePendingCopy: Bool
    ) -> BrowserTabStateEnvelope? {
        let pending = pendingCopies[assignment]
        if consumePendingCopy { pendingCopies.removeValue(forKey: assignment) }
        if let pending,
            SamePage.restoresArchivedState(archivedURL: pending.url, tabURL: url)
        {
            return pending
        }
        guard let archive,
            let archived = archive.archivedState(profileID: assignment.profileID, tabID: assignment.tabID),
            let envelope = BrowserTabStateEnvelope.decode(archived),
            envelope.isReadable,
            SamePage.restoresArchivedState(archivedURL: envelope.url, tabURL: url)
        else { return nil }
        return envelope
    }

    /// Only membership changes warrant another directory sweep. Closed tabs
    /// retain state until they leave both the live and archived tab collections.
    func prune(keeping tabIDsByProfileID: [UUID: Set<UUID>]) {
        guard let archive, !tabIDsByProfileID.isEmpty,
            tabIDsByProfileID != lastPrunedTabIDsByProfileID
        else { return }
        lastPrunedTabIDsByProfileID = tabIDsByProfileID
        archive.pruneStates(keeping: tabIDsByProfileID)
    }

    func discardState(matching assignment: BrowserTabRuntimeAssignment) {
        pendingCopies.removeValue(forKey: assignment)
        removeState(profileID: assignment.profileID, tabID: assignment.tabID)
    }

    func removeState(profileID: UUID, tabID: UUID) {
        archive?.removeState(profileID: profileID, tabID: tabID)
    }

    func removeStates(profileID: UUID) {
        archive?.removeStates(profileID: profileID)
    }

    func flushPendingWrites() async {
        await archive?.flushPendingWrites()
    }
}
