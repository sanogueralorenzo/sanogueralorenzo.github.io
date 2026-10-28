import Foundation

extension PageInputDelivered {
    @MainActor func deliver(to page: EnginePage) {
        page.agentWaits.settle(self)
    }
}
