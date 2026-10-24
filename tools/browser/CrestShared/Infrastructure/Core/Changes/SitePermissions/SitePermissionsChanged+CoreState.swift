import Foundation

extension SitePermissionsChanged {
    /// A Space that keeps no choices leaves the map. Every change advances the
    /// revision, since a session choice changes decisions without changing a
    /// kept record.
    @MainActor func apply(to state: CoreState) {
        state.sitePermissions[spaceID] = records.isEmpty ? nil : records
        state.sitePermissionRevision &+= 1
    }

    @MainActor func apply(to core: CrestCore, in batch: inout CoreChangeBatch) {
        batch.notificationAccessChanged = true
        apply(to: core.state)
        batch.permissionChanges.append(self)
    }
}
