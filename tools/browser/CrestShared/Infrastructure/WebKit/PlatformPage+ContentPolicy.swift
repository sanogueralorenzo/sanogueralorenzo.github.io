import WebKit

extension BrowserPlatformPage {
    func applyContentBlocking(
        policy: ContentBlockingPolicy,
        balancedRuleList: WKContentRuleList?,
        activation: BrowserContentRuleListActivation = .onNextNavigation
    ) {
        applyContentBlocking(
            policy: policy,
            balancedRuleLists: balancedRuleList.map { [$0] } ?? [],
            activation: activation
        )
    }
}
