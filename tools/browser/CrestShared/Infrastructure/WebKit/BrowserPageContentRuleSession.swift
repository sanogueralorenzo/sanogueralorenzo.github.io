import Observation
import WebKit

/// Owns only Crest's rules on a controller that may also carry extension rules.
@Observable
@MainActor
final class BrowserPageContentRuleSession {
    private(set) var isActive: Bool
    @ObservationIgnored private(set) var ruleLists: [WKContentRuleList]

    init(ruleLists: [WKContentRuleList], additionalRuleList: WKContentRuleList?) {
        var installed = ruleLists
        if let additionalRuleList, !installed.contains(where: { $0 === additionalRuleList }) {
            installed.append(additionalRuleList)
        }
        self.ruleLists = installed
        isActive = !installed.isEmpty
    }

    /// A list refresh takes effect on the next navigation unless the user
    /// explicitly changed protection for this page. Never discard a form just
    /// because the filter lists were updated.
    func apply(
        policy: ContentBlockingPolicy,
        balancedRuleLists: [WKContentRuleList],
        to webView: WKWebView,
        reloadsImmediately: Bool
    ) {
        let desired = policy.blocksContent ? balancedRuleLists : []
        guard
            ruleLists.count != desired.count
                || !zip(ruleLists, desired).allSatisfy({ $0 === $1 })
        else { return }

        let controller = webView.configuration.userContentController
        for ruleList in ruleLists {
            controller.remove(ruleList)
        }
        for ruleList in desired {
            controller.add(ruleList)
        }
        ruleLists = desired
        isActive = !desired.isEmpty
        if reloadsImmediately { webView.reload() }
    }
}
