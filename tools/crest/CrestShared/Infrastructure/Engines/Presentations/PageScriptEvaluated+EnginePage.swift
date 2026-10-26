import Foundation

extension PageScriptEvaluated {
    @MainActor func deliver(to page: EnginePage) {
        page.agentWaits.settle(self)
    }
}
