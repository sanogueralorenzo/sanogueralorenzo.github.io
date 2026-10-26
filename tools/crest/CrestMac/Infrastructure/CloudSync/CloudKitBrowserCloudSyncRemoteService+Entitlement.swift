import Foundation
import Security

extension CloudKitBrowserCloudSyncRemoteService {
    /// Whether this process is entitled to `containerIdentifier`, read the way
    /// the platform signs it.
    static func currentProcessContainsContainer(
        _ containerIdentifier: String
    ) -> Bool {
        guard let task = SecTaskCreateFromSelf(nil) else { return false }
        let value = SecTaskCopyValueForEntitlement(
            task,
            containerEntitlementName as CFString,
            nil
        )
        return containerEntitlement(value, contains: containerIdentifier)
    }
}
