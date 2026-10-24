import WebKit

@MainActor
enum BrowserContentRuleListCompiler {
    static func compile(
        identifier: String,
        source: String,
        store: WKContentRuleListStore = .default()
    ) async throws -> WKContentRuleList {
        try await withCheckedThrowingContinuation { continuation in
            store.compileContentRuleList(
                forIdentifier: identifier,
                encodedContentRuleList: source
            ) { ruleList, error in
                if let ruleList {
                    continuation.resume(returning: ruleList)
                    return
                }
                continuation.resume(
                    throwing: error ?? BrowserContentBlockingError.compilationFailed
                )
            }
        }
    }

    static func lookUp(
        identifier: String,
        store: WKContentRuleListStore = .default()
    ) async throws -> WKContentRuleList {
        try await withCheckedThrowingContinuation { continuation in
            store.lookUpContentRuleList(forIdentifier: identifier) { ruleList, error in
                if let ruleList {
                    continuation.resume(returning: ruleList)
                    return
                }
                continuation.resume(
                    throwing: error ?? BrowserContentBlockingError.ruleListUnavailable
                )
            }
        }
    }

    static func remove(
        identifier: String,
        store: WKContentRuleListStore = .default()
    ) async {
        await withCheckedContinuation { continuation in
            store.removeContentRuleList(forIdentifier: identifier) { _ in
                continuation.resume()
            }
        }
    }

    /// Every identifier the store currently holds a compiled list for, including
    /// lists compiled by other clients of the same store.
    static func availableIdentifiers(
        store: WKContentRuleListStore = .default()
    ) async -> [String] {
        await withCheckedContinuation { continuation in
            store.getAvailableContentRuleListIdentifiers { identifiers in
                continuation.resume(returning: identifiers ?? [])
            }
        }
    }
}
