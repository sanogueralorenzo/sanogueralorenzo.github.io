import Foundation
import CryptoKit
import Security

struct Clip: Codable, Equatable {
    struct Format: Codable, Equatable { var type: String; var data: String }
    enum Kind: String, Codable { case text, url, image, file }
    var id: String
    var kind: Kind
    var content: String
    var sourceAppId: String?
    var sourceAppName: String?
    var title: String?
    var thumbnail: String?
    var width: Int?
    var height: Int?
    var representations: [[Format]]?
    var createdAt: Double

    var appName: String { sourceAppName ?? "Unknown app" }
    var summary: String { title ?? content }
}

struct ClipboardPolicy: Codable {
    var maxItems = 200
    var retentionDays: Double? = 7
    var excludedAppIds: [String] = []
}

/// History and settings are owned by the serial queue.
final class ClipboardStore {
    private struct Settings: Codable { var clipboard: ClipboardPolicy }
    private struct Envelope: Codable { var version: Int; var iv: Data; var authTag: Data; var ciphertext: Data }
    private let queue = DispatchQueue(label: "sh.clipboard.history", qos: .utility)
    private let directory: URL
    private let review: Bool
    private var key: SymmetricKey?
    private var saved: [Clip] = []
    private var policy = ClipboardPolicy()
    private var ready = false
    var onChange: (([Clip], ClipboardPolicy, String?, Bool) -> Void)?

    init(directory: URL, review: Bool) { self.directory = directory; self.review = review }
    private var historyURL: URL { directory.appendingPathComponent("clipboard.json") }
    private var settingsURL: URL { directory.appendingPathComponent("settings.json") }

    func prune() { change { self.pruned($0) } }

    func finishWrites() { queue.sync {} }

    func load() {
        queue.async {
            do {
                try FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                if FileManager.default.fileExists(atPath: self.settingsURL.path) {
                    self.policy = try JSONDecoder().decode(Settings.self, from: Data(contentsOf: self.settingsURL)).clipboard
                    guard self.policy.maxItems >= 0, self.policy.retentionDays == nil || self.policy.retentionDays! >= 0 else { throw Self.failure("Invalid history settings.") }
                }
                self.key = try self.loadKey()
                if FileManager.default.fileExists(atPath: self.historyURL.path) {
                    let envelope = try JSONDecoder().decode(Envelope.self, from: Data(contentsOf: self.historyURL))
                    guard envelope.version == 1 else { throw Self.failure("Unsupported history version.") }
                    let box = try AES.GCM.SealedBox(nonce: AES.GCM.Nonce(data: envelope.iv), ciphertext: envelope.ciphertext, tag: envelope.authTag)
                    self.saved = try JSONDecoder().decode([Clip].self, from: AES.GCM.open(box, using: self.key!))
                }
                self.ready = true
                self.publish()
                self.change { self.pruned($0) }
            } catch {
                self.ready = false
                self.publish("History is unavailable. Capture is paused and existing files are untouched. \(error.localizedDescription)")
            }
        }
    }

    func capture(_ clip: Clip) {
        change { clips in
            var clip = clip
            let existing = clips.first { $0.sourceAppId == clip.sourceAppId && $0.kind == clip.kind && $0.content == clip.content && $0.representations == clip.representations }
            if let existing { clip.id = existing.id }
            let next = self.pruned([clip] + clips.filter { $0.id != clip.id })
            guard next.contains(where: { $0.id == clip.id }) else {
                throw Self.failure("This copy exceeds the saved history limits.")
            }
            return next
        }
    }

    func clear() { change { _ in [] } }

    func setRetention(days: Double) {
        queue.async {
            guard self.ready, self.policy.retentionDays != days else { return }
            do {
                var next = self.policy
                next.retentionDays = days
                try self.write(JSONEncoder().encode(Settings(clipboard: next)), to: self.settingsURL)
                self.policy = next
                self.publish()
                self.prune()
            } catch { self.publish("Could not save the history interval: \(error.localizedDescription)") }
        }
    }

    private func pruned(_ clips: [Clip]) -> [Clip] {
        let cutoff = policy.retentionDays.map { Date().timeIntervalSince1970 * 1000 - $0 * 86_400_000 }
        return Array(clips.filter { clip in cutoff.map { clip.createdAt >= $0 } ?? true }.prefix(policy.maxItems))
    }

    private func change(_ transform: @escaping ([Clip]) throws -> [Clip]) {
        queue.async {
            guard self.ready, let key = self.key else { return }
            do {
                var next = try transform(self.saved)
                guard next != self.saved else { return }
                var data = try JSONEncoder().encode(next)
                while data.count > 64 * 1024 * 1024, next.count > 1 {
                    next.removeLast()
                    data = try JSONEncoder().encode(next)
                }
                guard data.count <= 64 * 1024 * 1024 else { throw Self.failure("This copy exceeds the 64 MB history limit.") }
                let box = try AES.GCM.seal(data, using: key)
                let envelope = Envelope(version: 1, iv: Data(box.nonce), authTag: box.tag, ciphertext: box.ciphertext)
                try self.write(JSONEncoder().encode(envelope), to: self.historyURL)
                self.saved = next
                self.publish()
            } catch { self.publish("Could not save history. Existing clips are preserved. \(error.localizedDescription)") }
        }
    }

    private func publish(_ error: String? = nil) {
        let clips = saved, policy = policy, available = ready
        DispatchQueue.main.async { self.onChange?(clips, policy, error, available) }
    }

    private func write(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private func loadKey() throws -> SymmetricKey {
        let historyExists = FileManager.default.fileExists(atPath: historyURL.path)
        if review {
            let url = directory.appendingPathComponent("review.key")
            if FileManager.default.fileExists(atPath: url.path) {
                let data = try Data(contentsOf: url)
                guard data.count == 32 else { throw Self.failure("The review key is invalid.") }
                return SymmetricKey(data: data)
            }
            guard !historyExists else { throw Self.failure("The review key is missing.") }
            let key = SymmetricKey(size: .bits256)
            try write(key.withUnsafeBytes { Data($0) }, to: url)
            return key
        }
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "sh.clipboard.Desktop.clipboard", kSecAttrAccount as String: "default"]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query.merging([kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]) { _, new in new } as CFDictionary, &result)
        if status == errSecSuccess, let data = result as? Data, data.count == 32 { return SymmetricKey(data: data) }
        guard status == errSecItemNotFound, !historyExists else { throw Self.failure("The clipboard key is unavailable in Keychain.") }
        let key = SymmetricKey(size: .bits256)
        let add = query.merging([kSecValueData as String: key.withUnsafeBytes { Data($0) }]) { _, new in new }
        guard SecItemAdd(add as CFDictionary, nil) == errSecSuccess else { throw Self.failure("Could not save the clipboard key in Keychain.") }
        return key
    }

    private static func failure(_ message: String) -> NSError { NSError(domain: "Clipboard", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
}
