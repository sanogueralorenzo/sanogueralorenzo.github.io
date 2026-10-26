import Foundation

extension BrowserStore {
    /// Closing a saved native view dismisses its presentation, retaining the
    /// document in Saved. Current copies continue through the normal close path.
    func dismissNativeTab(_ id: UUID, matching assignment: BrowserSpaceRuntimeAssignment) {
        guard let space = shownSpace, BrowserSpaceRuntimeAssignment(space: space) == assignment,
            selectedTabID(in: space.id) == id,
            space.tabs.model(id)?.nativeContent != nil
        else { return }
        selectDismissalFallback(afterDismissing: id)
    }

    @discardableResult
    func openGettingStarted() -> UUID? {
        if let existing = shownSpace?.tabs.models.first(where: { $0.nativeTabContent == .gettingStarted }) {
            selectTab(existing.id)
            return existing.id
        }
        return openNativeTab(.gettingStarted)
    }

    @discardableResult
    func openGettingStartedAfterSetup(matching assignment: BrowserSpaceRuntimeAssignment)
        -> BrowserTabRuntimeAssignment?
    {
        guard !isPrivateBrowsing, let firstSpace = spaceModels.first,
            BrowserSpaceRuntimeAssignment(space: firstSpace) == assignment
        else { return nil }
        selectSpace(firstSpace.id)
        guard let tabID = openGettingStarted() else { return nil }
        return BrowserTabRuntimeAssignment(tabID: tabID, spaceID: assignment.spaceID, profileID: assignment.profileID)
    }

    /// Settings is one ordinary, closable native tab per Space. Repeated menu
    /// commands focus that tab without creating duplicates or opening WebKit.
    @discardableResult
    func openSettings() -> UUID? {
        if let existing = shownSpace?.tabs.models.first(where: { $0.nativeTabContent == .settings }) {
            selectTab(existing.id)
            return existing.id
        }
        return openNativeTab(.settings, placement: .current)
    }

    /// Native documents enter the same session mutation and persistence path as
    /// websites. No page pool or second selection model is owned by the document.
    @discardableResult
    func openNativeTab(_ view: NativeView, placement: TabPlacement = .saved) -> UUID? {
        guard let space = shownSpace else { return nil }
        return openSessionTab(.view(view), in: space.id, placement: placement)
    }
}
