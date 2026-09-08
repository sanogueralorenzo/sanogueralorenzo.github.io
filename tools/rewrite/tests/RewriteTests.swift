import AppKit

@MainActor
enum RewriteTests {
    static func editing() async throws {
        let boundary = String(repeating: "🦊", count: Editing.maximumUTF16 * 2)
        try expect(try Editing.validate(boundary) == boundary, "Valid UTF-16 boundary rejected")
        try expect(try Editing.validate(" \nText\n ") == " \nText\n ", "Formatting was trimmed")
        try await expectFailure(messageContains("no text")) { _ = try Editing.validate(" \n\t") }
        try await expectFailure(messageContains("too long")) { _ = try Editing.validate(boundary + "x") }
    }

    static func clipboard() async throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString("Old text", forType: .string)
        let result = " Might arrive Friday, 12 June: 42 🦊.\n"
        try RewriteClipboard.copy(result, to: pasteboard)
        try expect(pasteboard.string(forType: .string) == result, "Copied text lost formatting or content")
        let changeCount = pasteboard.changeCount
        try await expectFailure(messageContains("no text")) {
            try RewriteClipboard.copy(" \n", to: pasteboard)
        }
        try expect(pasteboard.changeCount == changeCount && pasteboard.string(forType: .string) == result, "Invalid output changed the clipboard")
    }

}
