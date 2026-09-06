import Foundation
import CryptoKit

enum ClipboardHistoryTests {
    static func run() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ClipboardStore(directory: directory, review: true)
        store.load()
        store.finishWrites()

        func clip(_ id: String, content: String = "text", age: Double = 0) -> Clip {
            Clip(id: id, kind: .text, content: content, sourceAppId: id,
                 createdAt: (Date().timeIntervalSince1970 - age) * 1000)
        }
        func capture(_ clip: Clip) {
            store.capture(clip)
            store.finishWrites()
        }
        func history() throws -> [Clip] {
            let key = SymmetricKey(data: try Data(contentsOf: directory.appendingPathComponent("review.key")))
            let data = try Data(contentsOf: directory.appendingPathComponent("clipboard.json"))
            let envelope = try JSONSerialization.jsonObject(with: data) as! [String: Any]
            func bytes(_ name: String) -> Data { Data(base64Encoded: envelope[name] as! String)! }
            let box = try AES.GCM.SealedBox(nonce: AES.GCM.Nonce(data: bytes("iv")), ciphertext: bytes("ciphertext"), tag: bytes("authTag"))
            let plaintext = try AES.GCM.open(box, using: key)
            precondition(plaintext.count <= 64 * 1024 * 1024)
            return try JSONDecoder().decode([Clip].self, from: plaintext)
        }

        let escaped = clip("escaped", content: "quote \" slash / newline\n emoji 🌱")
        let exactBytes = try JSONEncoder().encode([escaped]).count
        let (retained, encoded) = try ClipboardStore.encodeHistory([escaped, clip("older")], maximumBytes: exactBytes)
        precondition(retained == [escaped] && encoded.count == exactBytes)
        let decoded = try JSONDecoder().decode([Clip].self, from: encoded)
        precondition(decoded == retained)
        do {
            _ = try ClipboardStore.encodeHistory([escaped], maximumBytes: exactBytes - 1)
            preconditionFailure("One byte over the limit must fail")
        } catch {}
        let (_, empty) = try ClipboardStore.encodeHistory([])
        precondition(empty == Data("[]".utf8))
        print("PASS: exact JSON byte boundaries, escaping, and empty history")

        let pending = DispatchSemaphore(value: 0)
        let beforeClear = clip("before-clear"), afterClear = clip("after-clear")
        store.capture {
            precondition(!Thread.isMainThread, "Capture preparation must run off the main thread")
            pending.wait()
            return beforeClear
        }
        store.clear()
        store.capture { afterClear }
        pending.signal()
        store.finishWrites()
        let ordered = try history()
        precondition(ordered == [afterClear], "Clear must run after earlier captures and before later ones")
        store.capture { throw NSError(domain: "test", code: 1) }
        store.finishWrites()
        let afterFailure = try history()
        precondition(afterFailure == ordered)
        store.clear()
        store.finishWrites()
        print("PASS: background preparation, Clear ordering, shutdown drain, and failure preservation")

        for index in 0..<201 { capture(clip("\(index)")) }
        var saved = try history()
        precondition(saved.count == 200 && saved.first?.id == "200" && saved.last?.id == "1")
        capture(clip("100"))
        saved = try history()
        precondition(saved.count == 200 && saved.first?.id == "100")
        capture(clip("expired", age: 8 * 86_400))
        let afterExpiry = try history()
        precondition(afterExpiry == saved)
        print("PASS: count limit, recopy ordering, expiry")

        let newest = clip("newest", content: String(repeating: "A", count: 128))
        let older = (0..<4).map { clip("older-\($0)") }
        let byteLimit = try JSONEncoder().encode([newest, older[0]]).count
        let (withinLimit, limitedData) = try ClipboardStore.encodeHistory([newest] + older, maximumBytes: byteLimit)
        precondition(withinLimit == [newest, older[0]] && limitedData.count == byteLimit)
        let reloaded = try JSONDecoder().decode([Clip].self, from: limitedData)
        precondition(reloaded == withinLimit)
        print("PASS: byte limit evicts multiple oldest entries and retains valid JSON")

        let reopened = ClipboardStore(directory: directory, review: true)
        reopened.load()
        reopened.finishWrites()
        reopened.capture(clip("after-restart"))
        reopened.finishWrites()
        let afterRestart = try history()
        precondition(afterRestart.map(\.id) == ["after-restart"] + saved.dropLast().map(\.id))
        print("PASS: encrypted history reloads after eviction")

        reopened.clear()
        reopened.capture(clip("yesterday", age: 86_400))
        reopened.capture(clip("recent"))
        reopened.finishWrites()
        // Simulate a shorter interval saved before the app restarts.
        try Data(#"{"clipboard":{"maxItems":200,"retentionDays":0.5,"excludedAppIds":[]}}"#.utf8)
            .write(to: directory.appendingPathComponent("settings.json"))
        let prunedOnLoad = ClipboardStore(directory: directory, review: true)
        var updates: [([Clip], Double?, String?, Bool)] = []
        prunedOnLoad.onChange = { clips, policy, error, available in updates.append((clips, policy.retentionDays, error, available)) }
        func drainUpdates() {
            var drained = false
            DispatchQueue.main.async { drained = true }
            let deadline = Date(timeIntervalSinceNow: 2)
            while !drained && Date() < deadline { RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.01)) }
            precondition(drained, "History callbacks timed out")
        }
        prunedOnLoad.load()
        prunedOnLoad.finishWrites()
        let afterLoad = try history()
        precondition(afterLoad.map(\.id) == ["recent"], "One drain must include startup pruning")
        drainUpdates()
        precondition(updates.count == 1 && updates[0].0 == afterLoad && updates[0].3 && updates[0].2 == nil)
        updates.removeAll()
        prunedOnLoad.setRetention(days: 0)
        prunedOnLoad.finishWrites()
        let afterRetention = try history()
        precondition(afterRetention.isEmpty, "One drain must include retention pruning")
        drainUpdates()
        precondition(updates.count == 1 && updates[0].0.isEmpty && updates[0].1 == 0 && updates[0].2 == nil)
        updates.removeAll()
        prunedOnLoad.setRetention(days: 7)
        prunedOnLoad.finishWrites()
        drainUpdates()
        precondition(updates.count == 1 && updates[0].1 == 7, "Policy changes must publish even when history is unchanged")
        print("PASS: load and retention prune in one operation and publish once")

        for failure in ["corrupt-history", "missing-key", "invalid-key", "invalid-settings"] {
            let profile = directory.appendingPathComponent(failure)
            try FileManager.default.createDirectory(at: profile, withIntermediateDirectories: true)
            let historyURL = profile.appendingPathComponent("clipboard.json")
            let keyURL = profile.appendingPathComponent("review.key")
            let original = Data("invalid encrypted history".utf8)
            try original.write(to: historyURL)
            if failure != "missing-key" { try Data(repeating: 0, count: failure == "invalid-key" ? 1 : 32).write(to: keyURL) }
            if failure == "invalid-settings" {
                try Data(#"{"clipboard":{"maxItems":-1,"excludedAppIds":[]}}"#.utf8)
                    .write(to: profile.appendingPathComponent("settings.json"))
            }
            let unavailable = ClipboardStore(directory: profile, review: true)
            var reportedUnavailable = false
            unavailable.onChange = { _, _, error, available in reportedUnavailable = !available && error != nil }
            unavailable.load()
            unavailable.capture(clip("must-not-save"))
            unavailable.clear()
            unavailable.finishWrites()
            drainUpdates()
            let preserved = try Data(contentsOf: historyURL)
            precondition(reportedUnavailable && preserved == original)
            if failure == "missing-key" { precondition(!FileManager.default.fileExists(atPath: keyURL.path)) }
        }
        print("PASS: unavailable history stays untouched and missing keys are not replaced")
    }
}
