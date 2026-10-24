import Observation
import WebKit

/// One page owner's view of WebKit's built-in content blocking: the rules
/// WebKit's binding compiled for every page it builds, and which Spaces of the
/// owner's workspace changed their protection since the owner last applied it.
@MainActor
@Observable
final class BrowserContentBlockingController {
    // MARK: - Variables

    @ObservationIgnored private let rules: WebKitContentRules
    @ObservationIgnored private var reconciledState: BrowserContentBlockingSessionState?

    /// Why the rules could not be compiled, when they could not.
    var errorDescription: String? { rules.errorDescription }
    /// The compiled rules a Space that blocks content applies, once compiled.
    var balancedRuleLists: [WKContentRuleList]? { rules.balancedRuleLists }

    // MARK: - Initializers

    /// A view of `rules`, or of no rules where no WebKit binding compiles any.
    init(rules: WebKitContentRules?) {
        self.rules = rules ?? WebKitContentRules(provider: nil)
    }

    // MARK: - Actions - Rules

    func prepare() async {
        await rules.prepare()
    }

    func invalidateRuleLists() {
        rules.invalidate()
    }

    /// Prepares the rule lists any Space of `workspace` needs, and answers
    /// what changed since the last reconciliation.
    func reconcile(in workspace: WorkspaceModel?) async -> BrowserContentBlockingUpdate {
        let state = BrowserContentBlockingSessionState(workspace: workspace)
        if state.policiesBySpaceID.values.contains(where: \.blocksContent) {
            await prepare()
        }
        let update = BrowserContentBlockingUpdate(state: state, previousState: reconciledState)
        reconciledState = state
        return update
    }

    func ruleLists(for policy: ContentBlockingPolicy) -> [WKContentRuleList] {
        rules.ruleLists(for: policy)
    }
}
