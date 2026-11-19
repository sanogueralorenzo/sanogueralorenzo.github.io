import CryptoKit
import Foundation
import WebKit

struct BrowserContentRuleCache: Sendable {
    static let extensionID = "com.itsbrowser.ubol.cached"
    static let extensionURL = "webkit-extension://browser-ubol"

    private struct Stamp: Codable {
        let version: String
        let sourceHash: String
        let rulesets: [String]
    }

    private let directory: URL
    private let sourceDirectory: URL
    private let version: String
    private var stampURL: URL { directory.appendingPathComponent("Ready.json") }

    init?(spaceID: UUID, profile: URL) {
        guard let bundleID = Bundle.main.bundleIdentifier,
            let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first,
            let package = BrowserContentExtension.packageHash,
            let webKitVersion = Bundle(for: WKWebView.self).object(forInfoDictionaryKey: "CFBundleVersion") as? String
        else { return nil }
        directory = profile.appendingPathComponent("ContentBlocking", isDirectory: true)
            .appendingPathComponent(spaceID.uuidString, isDirectory: true)
        sourceDirectory = library.appendingPathComponent("WebKit", isDirectory: true)
            .appendingPathComponent(bundleID, isDirectory: true)
            .appendingPathComponent("WebExtensions", isDirectory: true)
            .appendingPathComponent(spaceID.uuidString, isDirectory: true)
            .appendingPathComponent("com.itsbrowser.ubol", isDirectory: true)
        version = "1/\(package)/\(webKitVersion)/\(ProcessInfo.processInfo.operatingSystemVersionString)"
    }

    @MainActor
    func load() async -> (WKContentRuleList, [String])? {
        guard let bytes = try? Data(contentsOf: stampURL),
            let stamp = try? JSONDecoder().decode(Stamp.self, from: bytes),
            stamp.version == version, stamp.sourceHash == sourceHash(), !stamp.rulesets.isEmpty,
            let store = WKContentRuleListStore(url: directory),
            let list = try? await store.contentRuleList(forIdentifier: Self.extensionID)
        else { return nil }
        return (list, stamp.rulesets)
    }

    @MainActor
    func build(rulesets: [String]) async throws {
        guard let hash = sourceHash() else { return }
        let reader = Task.detached(priority: .utility) {
            try readRules(withHash: hash)
        }
        let json = try await withTaskCancellationHandler {
            try await reader.value
        } onCancel: {
            reader.cancel()
        }
        try Task.checkCancellation()
        guard sourceHash() == hash else { return }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let store = WKContentRuleListStore(url: directory),
            try await store.compileContentRuleList(forIdentifier: Self.extensionID, encodedContentRuleList: json) != nil
        else { return }
        try Task.checkCancellation()
        guard sourceHash() == hash else { return }
        let stamp = Stamp(version: version, sourceHash: hash, rulesets: rulesets)
        try JSONEncoder().encode(stamp).write(to: stampURL, options: .atomic)
    }

    func invalidate() {
        try? FileManager.default.removeItem(at: stampURL)
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }

    private func sourceHash() -> String? {
        let url = sourceDirectory.appendingPathComponent("State.plist")
        guard let data = try? Data(contentsOf: url),
            let state = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any]
        else { return nil }
        return state["LastLoadedDeclarativeNetRequestHash"] as? String
    }

    private func readRules(withHash hash: String) throws -> String {
        let url = sourceDirectory.appendingPathComponent("DeclarativeNetRequestContentRuleList.data")
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard data.count > 65 else { throw CocoaError(.fileReadCorruptFile) }
        let (format, size) = data.withUnsafeBytes {
            ($0.loadUnaligned(as: UInt32.self).littleEndian,
             $0.loadUnaligned(fromByteOffset: 4, as: UInt64.self).littleEndian)
        }
        guard format == 21, size > 1, size <= data.count - 64, data[64] <= 1,
            let source = String(data: data[65..<(64 + Int(size))], encoding: data[64] == 1 ? .isoLatin1 : .utf16LittleEndian)
        else { throw CocoaError(.fileReadCorruptFile) }
        let utf8 = Data(source.utf8)
        let digest = Insecure.SHA1.hash(data: utf8).map { String(format: "%02x", $0) }.joined()
        guard hash.split(separator: "-").first?.lowercased() == digest,
            var rules = try JSONSerialization.jsonObject(with: utf8) as? [[String: Any]], !rules.isEmpty
        else { throw CocoaError(.fileReadCorruptFile) }
        for index in rules.indices {
            guard var action = rules[index]["action"] as? [String: Any],
                var redirect = action["redirect"] as? [String: Any],
                let path = redirect.removeValue(forKey: "extension-path") as? String else { continue }
            guard path.hasPrefix("/") else { throw CocoaError(.fileReadCorruptFile) }
            redirect["url"] = Self.extensionURL + path
            action["redirect"] = redirect
            rules[index]["action"] = action
        }
        try Task.checkCancellation()
        let translated = try JSONSerialization.data(withJSONObject: rules, options: .withoutEscapingSlashes)
        guard let json = String(data: translated, encoding: .utf8) else { throw CocoaError(.fileWriteInapplicableStringEncoding) }
        return json
    }
}
