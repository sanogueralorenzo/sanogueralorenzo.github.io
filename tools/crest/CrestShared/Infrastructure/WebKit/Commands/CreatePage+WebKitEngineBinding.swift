import Foundation

extension CreatePage {
    /// A page the platform asked for is built for its Space. A page the core
    /// moved from another engine is built for its owner, which takes it
    /// before the core loads it. WebKit reports whether it created the page.
    @MainActor func perform(on binding: WebKitEngineBinding) {
        guard let engines = binding.engines else { return }
        if let request = engines.request(pageID) {
            let space = engines.core.state.workspaces[request.intent.workspaceID]?.spaces.model(request.intent.spaceID)
            request.built = binding.keep(binding.build(self, in: space, popup: nil))
        } else if let moving = engines.page(pageID), let state = moving.state {
            // The core moved a page the platform already hosts to WebKit:
            // its owner takes the new page before the core loads it.
            let space = engines.core.state.workspaces[state.workspaceID]?.spaces.model(state.spaceID)
            engines.handOver(binding.keep(binding.build(self, in: space, popup: nil)), movedPage: moving)
        } else {
            engines.report(PageCreationFailed(pageID: pageID), from: binding)
            return
        }
        engines.report(PageCreated(pageID: pageID), from: binding)
    }
}
