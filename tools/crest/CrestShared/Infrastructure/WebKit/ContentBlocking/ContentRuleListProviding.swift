import WebKit

@MainActor
protocol BrowserContentRuleListProviding: AnyObject {
    func balancedRuleLists() async throws -> [WKContentRuleList]
}
