import Foundation

public struct SessionInvalidationResult {
    public let terminatedAppPIDs: [Int32]
    public let terminatedCliPIDs: [Int32]
    public let failedPIDs: [Int32]

    public var terminatedCount: Int {
        terminatedAppPIDs.count + terminatedCliPIDs.count
    }

    public var hadTargets: Bool {
        terminatedCount > 0 || !failedPIDs.isEmpty
    }
}
