import Observation
import SwiftUI

/// Validates and commits a row's reorder session from native input phases.
/// Folder headers use their enclosing section for measurement and displacement.
struct BrowserSidebarReorderSourceModifier: ViewModifier {
    let item: BrowserSidebarReorderItem
    let section: BrowserSidebarReorderSection
    let reorder: BrowserSidebarReorderContext

    var parentItemID: BrowserSidebarReorderItemID?
    var registersContainer = true
    var isEnabled = true

    @Environment(\.browserSidebarWindowDrop) private var windowDrop
    @State private var input = BrowserSidebarReorderInputSession()

    private var state: BrowserSidebarReorderState { reorder.state }
    private var ownsLift: Bool {
        input.ownsLift(in: state)
    }

    func body(content: Content) -> some View {
        // Selecting a drop destination must not cancel the source's active
        // gesture or discard its frozen geometry before the drop commits.
        let acceptsInput = isEnabled || ownsLift
        Group {
            if registersContainer {
                content.browserSidebarReorderContainer(
                    item: item, section: section, reorder: reorder, parentItemID: parentItemID,
                    isEnabled: acceptsInput)
            } else {
                content
            }
        }
        .modifier(
            BrowserPlatformSidebarReorderLiftGesture(isEnabled: acceptsInput, moved: moveLift, released: releaseLift))
    }

    // MARK: - Actions - Lifting

    /// Keeps captured selection and live source authorization with the shared
    /// session as the pointer moves: a lift another source took rejects the
    /// rest of this gesture, and an unclaimed one begins here.
    private func moveLift(from startLocation: CGPoint, to location: CGPoint) {
        if input.liftSessionToken != nil, !ownsLift {
            input.liftSessionToken = nil
            input.rejectedGesture = true
            return
        }
        if input.rejectedGesture { return }
        // A retained source can receive a callback before SwiftUI has
        // rendered a Space/profile/lock change. Recheck live authorization.
        if ownsLift {
            input.move(to: location, source: source, reorder: reorder)
            return
        }
        guard source.isAvailable(in: reorder), isEnabled,
            reorder.browser.selectedSpaceID == item.spaceAssignment.spaceID,
            !state.hasLiftInFlight
        else { return }
        guard let (lifted, liftedSection) = liftedItem(in: reorder) else {
            input.rejectedGesture = true
            return
        }
        state.begin(item: lifted, section: liftedSection, at: startLocation, plan: reorder.plan(for: lifted))
        input.liftSessionToken = state.sessionToken
        #if os(macOS)
            input.retainPointerContinuation(source: source, reorder: reorder, windowDrop: windowDrop)
        #endif
        state.update(pointer: location)
    }

    /// Commits the lift this source holds as the pointer lets go, and lets a
    /// rejected gesture go without activating the row.
    private func releaseLift() {
        if input.liftSessionToken != nil, !ownsLift {
            input.liftSessionToken = nil
            return
        }
        if input.rejectedGesture {
            input.rejectedGesture = false
            state.suppressActivation()
            return
        }
        guard ownsLift else { return }
        input.release(source: source, reorder: reorder, windowDrop: windowDrop)
    }

    private var source: BrowserSidebarReorderInputSession.Source {
        .init(item: item, section: section, parentItemID: parentItemID)
    }

    /// What pulling this row lifts: the row alone, or the window's selection
    /// when it holds the row, as the core previews it. A selection lifts as
    /// the split or folder around this row when one of its picks is that
    /// split or holds this row. Pinned tabs a selection would carry with
    /// others are let go first; nil when that leaves this row behind.
    private func liftedItem(
        in reorder: BrowserSidebarReorderContext
    ) -> (BrowserSidebarReorderItem, BrowserSidebarReorderSection)? {
        let browser = reorder.browser
        guard let firstID = item.firstSelectionID,
            var captured = BrowserSidebarSelection.capture(for: firstID, in: browser)
        else {
            return (item, section)
        }
        if let remaining = browser.tabMultiSelection.releasePinnedTabs(from: captured) {
            guard let recaptured = BrowserSidebarSelection.capture(remaining, in: browser),
                firstID.tabID.map(recaptured.ids.contains) ?? true
            else { return nil }
            captured = recaptured
        }
        guard let space = browser.spaceModel(item.spaceAssignment.spaceID) else { return nil }
        var lifted = item.selecting(captured)
        var liftedSection = section
        if let parentItemID, case .splitGroup(let groupID) = parentItemID, lifted.selectionRowIDs.contains(parentItemID)
        {
            lifted = .splitGroup(
                BrowserSplitGroupDragItem(
                    groupID: groupID, spaceID: space.id, profileID: space.profileID,
                    memberTabIDs: space.splitMembers(of: groupID).map(\.id), selection: captured))
        }
        if !lifted.selectionRowIDs.contains(item.id),
            let root = captured.rootItems.compactMap(\.folderID).first(where: { root in
                let holds = Set(space.folderChoices(inside: root).map(\.id)).union([root])
                if let folder = firstID.folderID { return holds.contains(folder) }
                return space.tabIDs(inFolder: root).contains { $0 == firstID.tabID }
            }), let folder = space.folders.model(root)
        {
            lifted = .folder(
                BrowserFolderDragItem(
                    folderID: root, spaceID: space.id, profileID: space.profileID, selection: captured))
            liftedSection = folder.reorderSection
        }
        return (lifted, liftedSection)
    }

}

/// Only the input token outlives a lazy row; no SwiftUI State storage is captured.
@Observable
@MainActor
final class BrowserSidebarReorderInputSession {
    var liftSessionToken: BrowserDragSessionToken?
    var rejectedGesture = false

    @MainActor
    struct Source {
        let item: BrowserSidebarReorderItem
        let section: BrowserSidebarReorderSection
        var parentItemID: BrowserSidebarReorderItemID?

        /// Whether the row still stands where it was lifted from: the Space
        /// has the same profile and still lists the row there. A locked Space's
        /// lift is the core's to refuse, in its own words.
        /// Used only for pointer actions, not while rendering or measuring rows.
        func isAvailable(in reorder: BrowserSidebarReorderContext) -> Bool {
            let assignment = item.spaceAssignment
            guard let space = reorder.browser.spaceModel(assignment.spaceID), space.profileID == assignment.profileID
            else { return false }
            return item.stands(in: space, section: section, parentItemID: parentItemID)
        }
    }

    func ownsLift(in state: BrowserSidebarReorderState) -> Bool {
        guard let liftSessionToken else { return false }
        return state.sessionToken == liftSessionToken
    }

    func retainPointerContinuation(
        source: Source, reorder: BrowserSidebarReorderContext, windowDrop: BrowserSidebarWindowDrop?
    ) {
        liftSessionToken = reorder.state.sessionToken
        guard let liftSessionToken else { return }
        reorder.state.retainPointerContinuation(session: liftSessionToken) {
            [
                self, weak state = reorder.state, weak browser = reorder.browser,
                weak access = reorder.spaceAccess
            ] point, released in
            guard let state else { return }
            guard let browser, let access else {
                cancel(in: state)
                return
            }
            let context = BrowserSidebarReorderContext(browser: browser, spaceAccess: access, state: state)
            move(to: point, source: source, reorder: context)
            if released {
                release(source: source, reorder: context, windowDrop: windowDrop)
            }
        }
    }

    /// Moves the lift this session holds to `location`.
    func move(to location: CGPoint, source: Source, reorder: BrowserSidebarReorderContext) {
        guard holdsLift(from: source, in: reorder) else { return }
        let state = reorder.state
        if state.pointer != location { state.update(pointer: location) }
    }

    /// Drops the lift this session holds: out of the window when the window
    /// takes it, and otherwise where it landed in the sidebar.
    func release(source: Source, reorder: BrowserSidebarReorderContext, windowDrop: BrowserSidebarWindowDrop?) {
        guard holdsLift(from: source, in: reorder) else { return }
        let state = reorder.state
        if let lift = state.liftPreview, windowDrop?.perform(lift) == true {
            cancel(in: state)
            state.suppressActivation()
            return
        }
        liftSessionToken = nil
        // Commit once while the native release event still supplies tear-off coordinates.
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            // The application draws the lift's preview, so it keeps it to land.
            guard let drop = state.end(retainingPreview: true) else { return }
            reorder.commit(drop)
        }
    }

    /// Whether this session still holds the lift `source` began; one whose
    /// row no longer stands where it was lifted from is cancelled.
    private func holdsLift(from source: Source, in reorder: BrowserSidebarReorderContext) -> Bool {
        let state = reorder.state
        guard ownsLift(in: state) else { return false }
        guard source.isAvailable(in: reorder) else {
            cancel(in: state)
            return false
        }
        return true
    }

    func cancel(in state: BrowserSidebarReorderState) {
        guard let liftSessionToken else { return }
        self.liftSessionToken = nil
        state.cancel(session: liftSessionToken)
    }
}

extension View {
    func browserSidebarReorderSource(
        item: BrowserSidebarReorderItem,
        section: BrowserSidebarReorderSection,
        reorder: BrowserSidebarReorderContext,
        parentItemID: BrowserSidebarReorderItemID? = nil,
        registersContainer: Bool = true,
        isEnabled: Bool = true
    ) -> some View {
        modifier(
            BrowserSidebarReorderSourceModifier(
                item: item,
                section: section,
                reorder: reorder,
                parentItemID: parentItemID,
                registersContainer: registersContainer,
                isEnabled: isEnabled
            )
        )
    }
}
