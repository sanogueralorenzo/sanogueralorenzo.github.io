import AppKit
@main
@MainActor
enum ClipboardSearchTests {
    static func main() {
        _ = NSApplication.shared
        let menu = ClipboardMenu()
        let content = Mirror(reflecting: menu).children.first { $0.label == "content" }!.value as! NSView
        let search = Mirror(reflecting: menu).children.first { $0.label == "search" }!.value as! ClipboardSearch
        let window = NSWindow(contentRect: content.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = content
        for clips in [[], [Clip(id: "one", kind: .text, content: "Sample", createdAt: 0)]] {
            menu.update(clips: clips, retentionDays: 7)
            menu.menuWillOpen(NSMenu())
            content.layoutSubtreeIfNeeded()
            let height = content.frame.height
            let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "f", charactersIgnoringModifiers: "f", isARepeat: false, keyCode: 3)!
            precondition(window.performKeyEquivalent(with: event), "Window must route Command-F with \(clips.count) clips")
            precondition(search.isSearching && search.currentEditor() != nil, "Command-F must focus the search editor")
            precondition(content.frame.height == height, "Search focus must not resize the menu")
            print("PASS: Command-F focuses search with \(clips.count) clips without resizing")
            window.makeFirstResponder(nil)
        }
    }
}
