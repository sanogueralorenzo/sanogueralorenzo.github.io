import WebKit

@MainActor
protocol BrowserContentRuleListCompiling: AnyObject {
    func compile(
        identifiers: [String],
        sources: [String],
        store: WKContentRuleListStore
    ) async throws -> [WKContentRuleList]
}
