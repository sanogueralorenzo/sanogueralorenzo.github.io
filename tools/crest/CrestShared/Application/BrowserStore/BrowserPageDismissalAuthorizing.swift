import Foundation

/// Native page confirmation precedes a semantic close. The operation still
/// commits through the store's authority; a deferred result is not a commit.
@MainActor
protocol BrowserPageDismissalAuthorizing: AnyObject {
    func performDismissal(
        of assignments: [BrowserTabRuntimeAssignment],
        in browser: BrowserStore,
        operation: @escaping @MainActor () -> Bool
    ) -> Bool
}

extension BrowserStore {
    @discardableResult
    func performPageDismissal(
        of assignments: [BrowserTabRuntimeAssignment],
        operation: @escaping @MainActor () -> Bool
    ) -> Bool {
        let checked: @MainActor () -> Bool = { [weak self] in
            guard let self,
                assignments.allSatisfy({ assignment in
                    self.spaceModel(
                        matching: BrowserSpaceRuntimeAssignment(
                            spaceID: assignment.spaceID, profileID: assignment.profileID)
                    )?.tabs.contains(assignment.tabID) == true
                })
            else { return false }
            return operation()
        }
        guard let authorizer = family.pageDismissalAuthorizer else { return checked() }
        return authorizer.performDismissal(of: assignments, in: self, operation: checked)
    }
}
