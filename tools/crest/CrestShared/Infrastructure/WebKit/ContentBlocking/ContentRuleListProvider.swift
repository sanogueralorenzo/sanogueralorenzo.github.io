import WebKit

/// Compiles the core's bundled rule lists into a WebKit rule-list store once,
/// then hands out the compiled lists.
@MainActor
final class BrowserContentRuleListProvider: BrowserContentRuleListProviding {
    private let core: CrestCore
    private let ruleListStore: WKContentRuleListStore?
    private let compiler: any BrowserContentRuleListCompiling
    private var cachedRuleLists: [WKContentRuleList]?

    init(
        core: CrestCore,
        ruleListStore: WKContentRuleListStore? = .default(),
        compiler: any BrowserContentRuleListCompiling =
            BrowserContentRuleListCompilerAdapter()
    ) {
        self.core = core
        self.ruleListStore = ruleListStore
        self.compiler = compiler
    }

    /// The provider a launch uses: an isolated launch compiles into no store.
    static func forLaunch(
        core: CrestCore,
        launchEnvironment: BrowserLaunchEnvironment = .current
    ) -> BrowserContentRuleListProvider {
        launchEnvironment.requiresIsolation
            ? BrowserContentRuleListProvider(core: core, ruleListStore: nil)
            : BrowserContentRuleListProvider(core: core)
    }

    func balancedRuleLists() async throws -> [WKContentRuleList] {
        guard let ruleListStore else { return [] }
        if let cachedRuleLists { return cachedRuleLists }
        // The core composes Crest's bundled rules. Without them there is
        // nothing to compile, the same as a launch without a rule store.
        guard let rules = try? core.query(BalancedProtectionRules()) else { return [] }

        let ruleLists = try await compiler.compile(
            identifiers: [rules.identifier],
            sources: [rules.source],
            store: ruleListStore
        )
        cachedRuleLists = ruleLists
        return ruleLists
    }
}
