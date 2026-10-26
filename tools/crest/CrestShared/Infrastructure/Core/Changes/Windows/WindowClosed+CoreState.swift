import Foundation

extension WindowClosed {
    @MainActor func apply(to state: CoreState) {
        state.publish(nil, forKey: windowID, into: \.windowsStorage, as: \.windows)
    }
}
