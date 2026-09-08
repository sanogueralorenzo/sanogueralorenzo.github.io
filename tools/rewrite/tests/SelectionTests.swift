import Foundation

@MainActor
extension RewriteTests {
    static func selection() async throws {
        let fingerprint = SelectionFingerprint(value: "A 🦊 fox", range: NSRange(location: 2, length: 2), text: "🦊")
        check(fingerprint.isConsistent && fingerprint.replacing(with: "cat") == "A cat fox", "UTF-16 selection")
        check(!SelectionFingerprint(value: "abc", range: NSRange(location: Int.max, length: 1), text: "a").isConsistent, "range overflow rejected")
        check(!SelectionFingerprint(value: "abc", range: NSRange(location: 0, length: 0), text: "").isConsistent, "empty range rejected")
        check(!SelectionFingerprint(value: "abc", range: NSRange(location: 0, length: 1), text: "b").isConsistent, "mismatched range rejected")
        check(fingerprint != SelectionFingerprint(value: "B 🦊 fox", range: fingerprint.range, text: fingerprint.text), "surrounding text change rejected")
    }
}
