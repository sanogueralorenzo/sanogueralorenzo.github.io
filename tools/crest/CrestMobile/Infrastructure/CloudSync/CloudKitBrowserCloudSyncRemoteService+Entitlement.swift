import Foundation
#if targetEnvironment(simulator)
    import MachO
#endif

extension CloudKitBrowserCloudSyncRemoteService {
    /// Whether this process is entitled to `containerIdentifier`, read the way
    /// the platform signs it.
    static func currentProcessContainsContainer(
        _ containerIdentifier: String
    ) -> Bool {
        #if targetEnvironment(simulator)
            // Simulator builds carry entitlements in the executable rather than
            // a device provisioning profile. CKContainer traps when they are absent.
            guard let header = _dyld_get_image_header(0) else { return false }
            let header64 = UnsafeRawPointer(header).assumingMemoryBound(to: mach_header_64.self)
            var size: UInt = 0
            guard let bytes = getsectiondata(header64, "__TEXT", "__entitlements", &size), size > 0,
                let values = try? PropertyListSerialization.propertyList(
                    from: Data(bytes: bytes, count: Int(size)), options: [], format: nil) as? [String: Any]
            else { return false }
            return containerEntitlement(values[containerEntitlementName], contains: containerIdentifier)
        #else
            // Device installation validates the signed application configuration.
            return true
        #endif
    }
}
