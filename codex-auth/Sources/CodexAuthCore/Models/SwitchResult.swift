import Foundation

public struct SwitchResult {
    public let destination: URL
    public let backup: URL?
    public let sourceDescription: String
    public let invalidation: SessionInvalidationResult
}
