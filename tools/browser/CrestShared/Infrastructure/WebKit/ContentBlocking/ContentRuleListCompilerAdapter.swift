import WebKit

@MainActor
final class BrowserContentRuleListCompilerAdapter: BrowserContentRuleListCompiling {
    func compile(
        identifiers: [String],
        sources: [String],
        store: WKContentRuleListStore
    ) async throws -> [WKContentRuleList] {
        var lists: [WKContentRuleList] = []
        for (identifier, source) in zip(identifiers, sources) {
            if let existing = try? await BrowserContentRuleListCompiler.lookUp(
                identifier: identifier,
                store: store
            ) {
                lists.append(existing)
            } else {
                lists.append(
                    try await BrowserContentRuleListCompiler.compile(
                        identifier: identifier,
                        source: source,
                        store: store
                    )
                )
            }
        }
        return lists
    }
}
