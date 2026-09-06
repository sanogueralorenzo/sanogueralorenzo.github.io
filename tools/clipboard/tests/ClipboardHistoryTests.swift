import Foundation
import CryptoKit

@main
enum ClipboardHistoryTests {
    static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ClipboardStore(directory: directory, review: true)
        store.load()
        store.finishWrites()
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

        store.clear()
        store.finishWrites()
        for index in 0..<7 { capture(clip("small-\(index)", content: String(repeating: "A", count: 1024 * 1024))) }
        let payload = String(repeating: "A", count: 8 * 1024 * 1024)
        for index in 0..<9 {
            var image = clip("image-\(index)")
            image.kind = .image
            image.representations = [[Clip.Format(type: "public.png", data: payload)]]
            capture(image)
        }
        saved = try history()
        precondition(saved.map(\.id) == (2..<9).reversed().map { "image-\($0)" })
        print("PASS: byte limit evicts multiple oldest entries and keeps the latest copy")

        capture(clip("oversized", content: String(repeating: "B", count: 64 * 1024 * 1024)))
        let afterOversized = try history()
        precondition(afterOversized == saved)
        print("PASS: an oversized single entry preserves existing history")

        let reopened = ClipboardStore(directory: directory, review: true)
        reopened.load()
        reopened.finishWrites()
        reopened.finishWrites()
        reopened.capture(clip("after-restart"))
        reopened.finishWrites()
        let afterRestart = try history()
        precondition(afterRestart.map(\.id) == ["after-restart"] + saved.map(\.id))
        print("PASS: encrypted history reloads after eviction")
    }
}
