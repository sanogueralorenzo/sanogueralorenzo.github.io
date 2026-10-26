import Foundation

extension AgentLinkRequest {
    /// Takes what the helper behind `link` said on `agents`, as the agents'
    /// handler for each request says. A request the link adds fails to
    /// compile until the agents handle it.
    @MainActor func handle(on agents: BrowserMacAgents, from link: BrowserMacAgents.Link) {
        switch self {
        case .attach(let version, let client): agents.attach(link, version: version, client: client)
        case .call(let id, let name, let arguments): agents.call(id, name: name, arguments: arguments, from: link)
        }
    }
}
