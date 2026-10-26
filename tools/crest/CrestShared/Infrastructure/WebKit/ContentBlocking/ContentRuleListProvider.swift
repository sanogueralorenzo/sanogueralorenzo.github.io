import Foundation
import WebKit

/// Compiles the core's bundled rule lists once into this launch's own store.
@MainActor
final class BrowserContentRuleListProvider: BrowserContentRuleListProviding {
    // MARK: - Variables

    private let core: CrestCore
    private let ruleListStore: Result<WKContentRuleListStore, Error>
    private let compiler: any BrowserContentRuleListCompiling
    private let temporaryDirectory: URL?
    private var cachedRuleLists: [WKContentRuleList]?

    // MARK: - Initializers

    init(
        core: CrestCore,
        ruleListStore: WKContentRuleListStore = .default(),
        compiler: any BrowserContentRuleListCompiling = BrowserContentRuleListCompilerAdapter()
    ) {
        self.core = core
        self.ruleListStore = .success(ruleListStore)
        self.compiler = compiler
        temporaryDirectory = nil
    }

    private init(core: CrestCore, directory: URL, removesDirectoryOnDeinit: Bool) {
        self.core = core
        compiler = BrowserContentRuleListCompilerAdapter()
        temporaryDirectory = removesDirectoryOnDeinit ? directory : nil
        ruleListStore = Result {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            guard let store = WKContentRuleListStore(url: directory) else {
                throw BrowserContentBlockingError.ruleListUnavailable
            }
            return store
        }
    }

    deinit {
        if let temporaryDirectory { try? FileManager.default.removeItem(at: temporaryDirectory) }
    }

    // MARK: - Actions - Launch

    /// Named profiles cache rules beside their own session. Anonymous isolated
    /// launches use a temporary store that disappears with the provider.
    static func forLaunch(
        core: CrestCore,
        launchEnvironment: BrowserLaunchEnvironment = .current
    ) -> BrowserContentRuleListProvider {
        guard launchEnvironment.requiresIsolation else { return BrowserContentRuleListProvider(core: core) }
        if let directory = core.storageDirectory {
            return BrowserContentRuleListProvider(
                core: core, directory: directory.appendingPathComponent("ContentRules", isDirectory: true),
                removesDirectoryOnDeinit: false)
        }
        return BrowserContentRuleListProvider(
            core: core,
            directory: FileManager.default.temporaryDirectory.appendingPathComponent(
                "crest-content-rules-\(UUID().uuidString)", isDirectory: true),
            removesDirectoryOnDeinit: true)
    }

    // MARK: - Actions - Rules

    func balancedRuleLists() async throws -> [WKContentRuleList] {
        if let cachedRuleLists { return cachedRuleLists }
        let store = try ruleListStore.get()
        let rules = try core.query(BalancedProtectionRules())
        let ruleLists = try await compiler.compile(
            identifiers: [rules.identifier], sources: [rules.source], store: store)
        cachedRuleLists = ruleLists
        return ruleLists
    }
}
