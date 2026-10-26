import CloudKit

actor CloudKitBrowserCloudSyncRemoteService: BrowserCloudSyncRemoteService {
    /// The entitlement that lists the iCloud containers a process may open.
    static let containerEntitlementName = "com.apple.developer.icloud-container-identifiers"

    private let configuration: BrowserCloudSyncConfiguration
    private var container: CKContainer?
    private var database: CKDatabase?

    init(configuration: BrowserCloudSyncConfiguration) {
        self.configuration = configuration
    }

    func hasRequiredEntitlement() -> Bool {
        Self.currentProcessContainsContainer(
            configuration.containerIdentifier
        )
    }

    /// Whether a signed container entitlement value lists `containerIdentifier`.
    static func containerEntitlement(_ entitlementValue: Any?, contains containerIdentifier: String) -> Bool {
        guard let identifiers = entitlementValue as? [String] else { return false }
        return identifiers.contains(containerIdentifier)
    }

    func accountState() async throws -> CloudAccountState {
        let container = cloudContainer()
        database = container.privateCloudDatabase
        let status = try await container.accountStatus()
        return Self.accountState(for: status)
    }

    /// Every record in Crest's zone the core may read. One whose envelope is
    /// not Crest's is left out, as the core leaves out one whose payload it
    /// cannot read.
    func loadSnapshot() async throws -> [SyncRecord] {
        let database = database ?? cloudContainer().privateCloudDatabase
        self.database = database
        do {
            return try await BrowserCloudSnapshotLoader(
                database: database,
                codec: BrowserCloudRecordCodec(zoneName: configuration.zoneName)
            ).load().records
        } catch let error as CKError where error.code == .zoneNotFound {
            return []
        }
    }

    nonisolated func message(for error: any Error) -> String {
        if let syncError = error as? BrowserCloudSyncError {
            switch syncError {
            case .remoteChangeNotApplied:
                return "Crest couldn’t apply the latest changes from iCloud."
            case .accountCheckUnanswered:
                return "iCloud didn’t respond in time. Crest will retry automatically."
            }
        }
        if let rejection = error as? Rejection {
            return rejection.explanation
        }
        guard let cloudError = error as? CKError else {
            return String(describing: error)
        }
        switch cloudError.code {
        case .notAuthenticated:
            return "Sign in to iCloud to sync Crest."
        case .networkUnavailable, .networkFailure:
            return "Crest can’t reach iCloud right now."
        case .serviceUnavailable:
            return "iCloud is temporarily unavailable. Crest will retry automatically."
        case .requestRateLimited:
            return "iCloud is temporarily busy. Crest will retry automatically."
        case .quotaExceeded:
            return "Your iCloud storage is full."
        case .permissionFailure:
            return "This build is not permitted to use Crest’s iCloud container."
        default:
            return cloudError.localizedDescription
        }
    }

    private func cloudContainer() -> CKContainer {
        if let container { return container }
        let result = CKContainer(identifier: configuration.containerIdentifier)
        container = result
        return result
    }

    private static func accountState(for status: CKAccountStatus) -> CloudAccountState {
        switch status {
        case .available: .available
        case .noAccount: .noAccount
        case .restricted: .restricted
        case .temporarilyUnavailable: .temporarilyUnavailable
        case .couldNotDetermine: .couldNotDetermine
        @unknown default: .couldNotDetermine
        }
    }
}
