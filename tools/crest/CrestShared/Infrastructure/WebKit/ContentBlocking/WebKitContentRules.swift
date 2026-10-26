import Observation
import WebKit

/// The content rules WebKit's binding compiles once for every page it builds:
/// Crest's balanced protection, which a Space that blocks content applies.
@MainActor
@Observable
final class WebKitContentRules {
    // MARK: - Variables

    /// Why the rules could not be compiled, when they could not.
    private(set) var errorDescription: String?
    /// The compiled rules, once compiled.
    @ObservationIgnored private(set) var balancedRuleLists: [WKContentRuleList]?
    /// What compiles the rules; nil compiles none.
    @ObservationIgnored var provider: (any BrowserContentRuleListProviding)?

    // MARK: - Initializers

    init(provider: (any BrowserContentRuleListProviding)?) {
        self.provider = provider
    }

    // MARK: - Actions - Compiling

    /// Compiles the rules unless they already are.
    func prepare() async {
        guard balancedRuleLists == nil else { return }
        guard let provider else {
            balancedRuleLists = []
            return
        }
        do {
            balancedRuleLists = try await provider.balancedRuleLists()
            errorDescription = nil
        } catch {
            errorDescription = error.localizedDescription
        }
    }

    /// Forgets the compiled rules, which the next preparation compiles again.
    func invalidate() {
        balancedRuleLists = nil
    }

    /// The rules a Space with `policy` applies: none until they are compiled.
    func ruleLists(for policy: ContentBlockingPolicy) -> [WKContentRuleList] {
        policy.blocksContent ? balancedRuleLists ?? [] : []
    }
}
