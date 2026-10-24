import Foundation
import Observation

@Observable @MainActor
final class BrowserApplicationLaunch<Value> {
    private(set) var value: Value?
    private(set) var failure: BrowserSessionStartupFailure?
    private(set) var recoveryError: String?
    private let factory: () throws -> Value

    init(_ factory: @escaping () throws -> Value) {
        self.factory = factory
        retry()
    }

    func retry() {
        guard value == nil else { return }
        do {
            value = try factory()
            failure = nil
            recoveryError = nil
        } catch {
            failure =
                error as? BrowserSessionStartupFailure
                ?? BrowserSessionStartupFailure(storageDirectory: nil, underlying: error)
        }
    }

    func restore() {
        guard value == nil, let failure else { return }
        do {
            try failure.restore()
            recoveryError = nil
            retry()
        } catch {
            recoveryError = "The checkpoint could not be restored. Your original files have been preserved."
        }
    }
}
