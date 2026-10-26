import Foundation
import Security

protocol SecurityCredentialKeychainClient: Sendable {
    func copyMatching(
        _ query: [CFString: Any]
    ) -> (status: OSStatus, result: CFTypeRef?)
    func update(
        _ query: [CFString: Any],
        attributes: [CFString: Any]
    ) -> OSStatus
    func add(_ attributes: [CFString: Any]) -> OSStatus
    func delete(_ query: [CFString: Any]) -> OSStatus
}
