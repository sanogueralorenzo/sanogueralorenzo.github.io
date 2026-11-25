import CryptoKit
import Foundation
import WebKit

struct BrowserContentRuleCache: Sendable {
    static let extensionID = "com.itsbrowser.ubol.cached"
    static let extensionURL = "webkit-extension://browser-ubol"
    typealias Entry = (rules: WKContentRuleList, rulesets: [String])

    private struct Stamp: Codable {
        let version: String
        let sourceHash: String
        let rulesets: [String]
    }

    private let directory: URL
    private let spaceID: UUID?
    private let version: String
    private var stampURL: URL { directory.appendingPathComponent("Ready.json") }

    init?(profile: URL, packageHash: String, spaceID: UUID? = nil) {
        guard let webKitVersion = Bundle(for: WKWebView.self).object(forInfoDictionaryKey: "CFBundleVersion") as? String
        else { return nil }
        self.spaceID = spaceID
        directory = profile.appendingPathComponent("ContentBlocking", isDirectory: true)
            .appendingPathComponent(spaceID?.uuidString ?? "DefaultRules", isDirectory: true)
        let environment = "\(packageHash)/\(webKitVersion)/\(ProcessInfo.processInfo.operatingSystemVersionString)"
        version = if spaceID != nil {
            "2/\(environment)"
        } else {
            "1/\(environment)/\(Locale.preferredLanguages.joined(separator: ","))/\(Bundle.main.preferredLocalizations.joined(separator: ","))"
        }
    }

    @MainActor
    func load() async -> Entry? {
        guard let bytes = try? Data(contentsOf: stampURL),
            let stamp = try? JSONDecoder().decode(Stamp.self, from: bytes),
            stamp.version == version, !stamp.rulesets.isEmpty,
            spaceID == nil || stamp.sourceHash == Self.sourceHash(in: spaceID.flatMap(Self.sourceDirectory)),
            let store = WKContentRuleListStore(url: directory),
            let list = try? await store.contentRuleList(forIdentifier: Self.extensionID)
        else { return nil }
        return (list, stamp.rulesets)
    }

    @MainActor
    func build(rulesets: [String], from sourceID: UUID) async throws -> Entry? {
        guard let source = Self.sourceDirectory(for: sourceID), let hash = Self.sourceHash(in: source) else { return nil }
        let reader = Task.detached(priority: .utility) {
            try Self.readRules(in: source, withHash: hash)
        }
        let json = try await withTaskCancellationHandler {
            try await reader.value
        } onCancel: {
            reader.cancel()
        }
        try Task.checkCancellation()
        guard Self.sourceHash(in: source) == hash else { return nil }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        do { try FileManager.default.removeItem(at: stampURL) } catch CocoaError.fileNoSuchFile {}
        guard let store = WKContentRuleListStore(url: directory),
            let rules = try await store.compileContentRuleList(forIdentifier: Self.extensionID, encodedContentRuleList: json)
        else { return nil }
        try Task.checkCancellation()
        guard Self.sourceHash(in: source) == hash else { return nil }
        let stamp = Stamp(version: version, sourceHash: hash, rulesets: rulesets)
        try JSONEncoder().encode(stamp).write(to: stampURL, options: .atomic)
        return (rules, rulesets)
    }

    func invalidate() {
        try? FileManager.default.removeItem(at: stampURL)
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }

    static func canUseDefaultRules(in spaceID: UUID) -> Bool {
        guard let source = sourceDirectory(for: spaceID) else { return false }
        do {
            _ = try source.checkResourceIsReachable()
            return false
        } catch CocoaError.fileReadNoSuchFile {
            return true
        } catch {
            return false
        }
    }

    static func removeSeed(_ id: UUID) {
        guard let source = sourceDirectory(for: id) else { return }
        try? FileManager.default.removeItem(at: source.deletingLastPathComponent())
    }

    private static func sourceDirectory(for spaceID: UUID) -> URL? {
        guard let bundleID = Bundle.main.bundleIdentifier,
            let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
        else { return nil }
        return library.appendingPathComponent("WebKit", isDirectory: true)
            .appendingPathComponent(bundleID, isDirectory: true)
            .appendingPathComponent("WebExtensions", isDirectory: true)
            .appendingPathComponent(spaceID.uuidString, isDirectory: true)
            .appendingPathComponent("com.itsbrowser.ubol", isDirectory: true)
    }

    private static func sourceHash(in source: URL?) -> String? {
        guard let url = source?.appendingPathComponent("State.plist") else { return nil }
        guard let data = try? Data(contentsOf: url),
            let state = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any]
        else { return nil }
        return state["LastLoadedDeclarativeNetRequestHash"] as? String
    }

    private static func readRules(in directory: URL, withHash hash: String) throws -> String {
        let url = directory.appendingPathComponent("DeclarativeNetRequestContentRuleList.data")
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
