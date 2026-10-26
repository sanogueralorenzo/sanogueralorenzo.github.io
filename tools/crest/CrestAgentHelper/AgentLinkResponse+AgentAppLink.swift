import Foundation

extension AgentLinkResponse {
    /// Delivers what Crest said to the helper's link, as the link's handler
    /// for each response says. A response the link adds fails to compile
    /// until the link handles it.
    func deliver(to link: isolated AgentAppLink) {
        switch self {
        case .attached(let tools): link.receiveAttached(tools)
        case .refused(let reason): link.receiveRefusal(reason)
        case .result(let id, let result): link.receiveResult(result, for: id)
        }
    }
}
