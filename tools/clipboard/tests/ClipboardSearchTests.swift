import AppKit
@MainActor
enum ClipboardSearchTests {
    static func run() {
        _ = NSApplication.shared
        let menu = ClipboardMenu()
        let content = Mirror(reflecting: menu).children.first { $0.label == "content" }!.value as! NSView
        let search = Mirror(reflecting: menu).children.first { $0.label == "search" }!.value as! ClipboardSearch
        let window = NSWindow(contentRect: content.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = content
        let table = Mirror(reflecting: menu).children.first { $0.label == "table" }!.value as! ClipboardTable
        let first = Clip(id: "first", kind: .text, content: "First", createdAt: 0)
        let second = Clip(id: "second", kind: .text, content: "Second", createdAt: 0)
        menu.update(clips: [first], retentionDays: 7)
        precondition(menu.numberOfRows(in: table) == 0, "Closed updates must defer table refresh")
        menu.menuWillOpen(NSMenu())
        precondition(menu.numberOfRows(in: table) == 1)
        menu.menuDidClose(NSMenu())
        menu.update(clips: [first, second], retentionDays: 7)
        precondition(menu.numberOfRows(in: table) == 1)
        menu.menuWillOpen(NSMenu())
        precondition(menu.numberOfRows(in: table) == 2, "Opening must show the latest history")
        menu.update(clips: [second], retentionDays: 7)
        precondition(menu.numberOfRows(in: table) == 1, "Open menus must refresh immediately")
        print("PASS: closed menus defer refresh; opening and visible updates show current history")

        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8,
                                      samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                      bytesPerRow: 0, bitsPerPixel: 0)!
        let thumbnail = "data:image/png;base64," + bitmap.representation(using: .png, properties: [:])!.base64EncodedString()
        let image = Clip(id: "image", kind: .image, content: "Image", thumbnail: thumbnail, createdAt: 0)
        menu.update(clips: [image, image], retentionDays: 7)
        let imageCell = menu.tableView(table, viewFor: nil, row: 0) as! ClipboardItemView
        let otherCell = menu.tableView(table, viewFor: nil, row: 1) as! ClipboardItemView
        precondition(imageCell.imageView.image != nil && imageCell.imageView.image === otherCell.imageView.image)
        precondition(imageCell.toolTip == "Space to Preview")
        imageCell.setShortcut(nil)
        precondition(imageCell.shortcutField.isHidden && imageCell.shortcutField.stringValue.isEmpty)
        imageCell.setShortcut("⌘2")
        precondition(!imageCell.shortcutField.isHidden && imageCell.shortcutField.stringValue == "⌘2")
        let manyClips = (0..<50).map { index in
            Clip(id: "row-\(index)", kind: index < 9 ? .image : .text, content: "Row \(index)",
                 thumbnail: index < 9 ? thumbnail : nil, createdAt: 0)
        }
        menu.update(clips: manyClips, retentionDays: 7)
        content.layoutSubtreeIfNeeded()
        let initialCells = (0..<6).map { table.view(atColumn: 0, row: $0, makeIfNecessary: true)! }
        table.scrollRowToVisible(30)
        table.layoutSubtreeIfNeeded()
        let scrolledCells = (25...30).compactMap { table.view(atColumn: 0, row: $0, makeIfNecessary: true) as? ClipboardItemView }
        precondition(scrolledCells.contains { cell in initialCells.contains { $0 === cell } }, "Scrolling must recycle cells")
        for cell in scrolledCells {
            precondition(cell.toolTip == nil && cell.shortcutField.isHidden && cell.titleField.stringValue.hasPrefix("Row "),
                         "Recycled text cells must clear image hints and numbered shortcuts")
        }
        print("PASS: thumbnail cache and scrolling reuse without stale preview hints or shortcuts")
        menu.menuDidClose(NSMenu())
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
