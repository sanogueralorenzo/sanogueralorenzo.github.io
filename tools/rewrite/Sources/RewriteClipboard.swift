import AppKit

@MainActor
enum RewriteClipboard {
    static func copy(_ text: String, to pasteboard: NSPasteboard = .general) throws {
        let text = try Editing.validate(text)
        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else {
            throw RewriteError.message("Could not copy the rewrite. Try again.")
        }
    }
}
