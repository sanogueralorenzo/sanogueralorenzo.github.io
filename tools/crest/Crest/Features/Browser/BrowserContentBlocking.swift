import CryptoKit
import Foundation
import WebKit

/// The same bundled network and cosmetic rules, compiled directly for WebKit.
@MainActor
final class BrowserContentBlocking {
    static let shared = BrowserContentBlocking()
    private var compilation: Task<WKContentRuleList, Error>?
    private(set) var ready: WKContentRuleList?

    func rules() async throws -> WKContentRuleList {
        if let compilation {
            let value = try await compilation.value
            ready = value
            return value
        }
        let task = Task { @MainActor in
            guard let cosmeticURL = Bundle.main.url(forResource: "ContentBlockingCosmetics", withExtension: "json"),
                let hostsURL = Bundle.main.url(forResource: "ContentBlockingHosts", withExtension: "txt")
            else {
                throw CocoaError(.fileNoSuchFile)
            }
            var rules = try JSONSerialization.jsonObject(with: Data(contentsOf: cosmeticURL)) as? [[String: Any]] ?? []
            let hosts = try String(contentsOf: hostsURL, encoding: .utf8).split(separator: "\n").compactMap {
                line -> String? in
                guard !line.hasPrefix("#") else { return nil }
                let parts = line.split(whereSeparator: \.isWhitespace)
                return parts.count == 2 ? String(parts[1]) : nil
            }
            let resources = [
                "child-document", "image", "style-sheet", "script", "font", "raw", "svg-document",
                "media", "popup", "ping", "fetch", "websocket", "csp-report", "other",
            ]
            for host in Set(hosts).sorted() {
                let filter = "^[^:]+://+([^:/]+\\.)?" + host.replacingOccurrences(of: ".", with: "\\.") + "[:/]"
                rules.append([
                    "trigger": [
                        "url-filter": filter, "url-filter-is-case-sensitive": true,
                        "load-type": ["third-party"], "resource-type": resources,
                    ],
                    "action": ["type": "block"],
                ])
            }
            let data = try JSONSerialization.data(withJSONObject: rules, options: [.sortedKeys])
            let identifier = "Crest." + SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            if let existing: WKContentRuleList = await withCheckedContinuation({ continuation in
                WKContentRuleListStore.default().lookUpContentRuleList(forIdentifier: identifier) { list, _ in
                    continuation.resume(returning: list)
                }
            }) {
                return existing
            }
            return try await withCheckedThrowingContinuation { continuation in
                WKContentRuleListStore.default().compileContentRuleList(
                    forIdentifier: identifier, encodedContentRuleList: String(decoding: data, as: UTF8.self)
                ) { list, error in
                    if let list {
                        continuation.resume(returning: list)
                    } else {
                        continuation.resume(throwing: error ?? CocoaError(.coderInvalidValue))
                    }
                }
            }
        }
        compilation = task
        do {
            let value = try await task.value
            ready = value
            return value
        } catch {
            compilation = nil
            throw error
        }
    }
}
