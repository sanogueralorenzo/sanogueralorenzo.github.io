import AppKit

@MainActor
enum ValidationTests {
    static func providers() async throws {
        let name = "rewrite-provider-test-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        try expect(RewriteProvider.load(from: defaults) == .openai, "First launch must default to OpenAI")
        RewriteProvider.anthropic.save(to: defaults)
        try expect(RewriteProvider.load(from: UserDefaults(suiteName: name)!) == .anthropic, "Provider choice was not saved immediately")
        defaults.set("Claude CLI", forKey: "processor")
        try expect(RewriteProvider.load(from: defaults) == .anthropic, "Existing provider preference was lost")
        defaults.set("unknown", forKey: "processor")
        try expect(RewriteProvider.load(from: defaults) == .openai, "Unknown preference must use the default")
    }

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

    static func responses() async throws {
        func response(reason: String = "stop", complete: Bool = true, tool: Bool = false) throws -> Data {
            var content: [[String: Any]] = [["type": "thinking", "thinking": "Never replace with this"], ["type": "text", "text": " Keep\u{2028}formatting.\n"]]
            if tool { content.append(["type": "toolCall", "name": "bash"]) }
            var data = try JSONSerialization.data(withJSONObject: ["type": "message_end", "message": ["role": "assistant", "stopReason": reason, "content": content]])
            if complete { data.append(Data("\n{\"type\":\"agent_end\"}\n".utf8)) }
            return data
        }
        try expect(try PiService.parse(response()) == " Keep\u{2028}formatting.\n", "Non-text content leaked or formatting changed")
        for data in try [response(reason: "length"), response(reason: "aborted"), response(complete: false), response(tool: true), Data("not json".utf8)] {
            try await expectFailure(messageContains("completed rewrite")) { _ = try PiService.parse(data) }
        }
    }
}
