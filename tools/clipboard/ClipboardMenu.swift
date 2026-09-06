import AppKit

final class ClipboardSearch: NSSearchField {
    private(set) var isSearching = false
    var didFocus: (() -> Void)?
    override var acceptsFirstResponder: Bool { isSearching }
    override func becomeFirstResponder() -> Bool { isSearching && super.becomeFirstResponder() }
    func focus() {
        isSearching = true
        didFocus?()
        window?.makeFirstResponder(self)
    }
    func endSearch() { isSearching = false }
    override func mouseDown(with event: NSEvent) { focus(); super.mouseDown(with: event) }
}

final class ClipboardRow: NSTableRowView {
    override func drawSelection(in dirtyRect: NSRect) {
        NSColor(calibratedRed: 0.64, green: 0.54, blue: 0.84, alpha: 0.24).setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 0), xRadius: 8, yRadius: 8).fill()
    }
}

final class ClipboardTable: NSTableView {
    var onKey: ((NSEvent) -> Bool)?
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); window?.makeFirstResponder(self) }
    override func keyDown(with event: NSEvent) { if onKey?(event) != true { super.keyDown(with: event) } }
    override func performKeyEquivalent(with event: NSEvent) -> Bool { onKey?(event) == true || super.performKeyEquivalent(with: event) }
    var onHoverChange: (() -> Void)?
    private var hoverTracking: NSTrackingArea?
    private var hoverPoint: NSPoint?
    var hoveredRow: Int {
        guard let hoverPoint else { return -1 }
        let point = convert(hoverPoint, from: nil)
        return visibleRect.contains(point) ? row(at: point) : -1
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTracking { removeTrackingArea(hoverTracking) }
        let tracking = NSTrackingArea(rect: .zero, options: [.inVisibleRect, .activeAlways, .mouseMoved, .mouseEnteredAndExited], owner: self)
        addTrackingArea(tracking); hoverTracking = tracking
    }
    override func mouseMoved(with event: NSEvent) {
        hoverPoint = event.locationInWindow
        if hoveredRow >= 0 { selectRowIndexes(IndexSet(integer: hoveredRow), byExtendingSelection: false) }
        onHoverChange?()
    }
    override func mouseEntered(with event: NSEvent) { mouseMoved(with: event) }
    override func mouseExited(with event: NSEvent) { hoverPoint = nil; onHoverChange?() }
    override func mouseDown(with event: NSEvent) { mouseMoved(with: event); super.mouseDown(with: event) }
    func clearHover() { hoverPoint = nil }
}

@MainActor
final class ClipboardMenu: NSObject, NSMenuDelegate, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    var onOpen: (() -> Void)?
    var onCopy: ((Clip, Bool) -> Void)?
    var onPreview: ((Clip) -> Void)?
    var onClear: (() -> Void)?
    var onRetentionChange: ((Double) -> Void)?
    private let clipboardMenu = NSMenu()
    private let content = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 236))
    private let search = ClipboardSearch()
    private let table = ClipboardTable()
    private let historyScroll = NSScrollView()
    private let emptyState = NSView()
    private let emptyLabel = NSTextField(labelWithString: "No matching clips")
    private let tutorialCard = NSBox()
    private let emptyRows = NSStackView()
    private let clearItem = NSMenuItem(title: "Clear History", action: nil, keyEquivalent: "")
    private let clearNowItem = NSMenuItem(title: "Now", action: nil, keyEquivalent: "")
    private var retentionItems: [NSMenuItem] = []
    private var statusItem: NSStatusItem!
    private let previewItem = NSMenuItem(title: "Preview", action: nil, keyEquivalent: " ")
    private var copyItems: [NSMenuItem] = []
    private var clips: [Clip] = []
    private var filtered: [Clip] = []
    private var iconCache: [String: NSImage] = [:]
    private var menuOpen = false
    private var searchExpanded = false
    private var historyAvailable = false

    override init() { super.init(); configureContent(); configureMenu(); report(nil) }
    func update(clips: [Clip], available: Bool, retentionDays: Double?) {
        self.clips = clips; historyAvailable = available
        clearItem.isEnabled = available
        clearNowItem.isEnabled = available && !clips.isEmpty
        for item in retentionItems { item.state = retentionDays == Double(item.tag) / 1440 ? .on : .off }
        reload()
    }
    func report(_ error: String?) { statusItem.button?.toolTip = error ?? "Clipboard · ⌥⇧V" }
    func toggle() { menuOpen ? dismiss() : show() }
    func show() { if !menuOpen { statusItem.button?.performClick(nil) } }
    func dismiss() { clipboardMenu.cancelTracking() }
    func menuWillOpen(_ menu: NSMenu) {
        menuOpen = true; onOpen?()
        searchExpanded = false; search.endSearch(); search.stringValue = ""
        table.clearHover(); table.deselectAll(nil); reload()
    }
    func menuDidClose(_ menu: NSMenu) { menuOpen = false; search.endSearch() }
    func controlTextDidEndEditing(_ obj: Notification) { search.endSearch(); updatePreviewShortcut() }
    func controlTextDidChange(_ obj: Notification) { searchExpanded = true; reload() }
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.moveDown(_:)): moveSelection(by: 1)
        case #selector(NSResponder.moveUp(_:)): moveSelection(by: -1)
        case #selector(NSResponder.insertNewline(_:)): pasteClip()
        case #selector(NSResponder.cancelOperation(_:)): dismiss()
        default: return false
        }
        return true
    }
    private func moveSelection(by offset: Int) {
        guard !filtered.isEmpty else { return }
        let row = max(0, min(filtered.count - 1, table.selectedRow + offset))
        table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        table.scrollRowToVisible(row); search.endSearch(); content.window?.makeFirstResponder(table); updatePreviewShortcut()
    }
    private func reload() {
        let id = selected?.id
        let query = search.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        filtered = clips.filter { clip in
            query.isEmpty || [clip.content, clip.title ?? "", clip.appName].contains { $0.localizedCaseInsensitiveContains(query) }
        }
        for item in copyItems { item.isEnabled = filtered.indices.contains(item.tag) }
        table.reloadData()
        if !filtered.isEmpty { table.selectRowIndexes(IndexSet(integer: filtered.firstIndex { $0.id == id } ?? 0), byExtendingSelection: false) }
        updateContentSize(); updatePreviewShortcut()
    }
    private func configureContent() {
        let root = content
        let stack = NSStackView()
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 10), stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -10), stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 10), stack.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -10)])
        search.placeholderString = "Search"
        search.delegate = self
        search.didFocus = { [weak self] in
            self?.searchExpanded = true
            self?.updateContentSize()
            self?.updatePreviewShortcut()
        }
        search.sendsSearchStringImmediately = true
        search.font = .systemFont(ofSize: 13)
        search.setAccessibilityLabel("Search clips or apps")
        add(search, to: stack)
        search.heightAnchor.constraint(equalToConstant: 26).isActive = true
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("clip")); column.width = content.frame.width - 22
        table.addTableColumn(column)
        table.headerView = nil; table.backgroundColor = .clear
        table.rowHeight = 30; table.intercellSpacing = NSSize(width: 0, height: 2)
        table.style = .plain; table.selectionHighlightStyle = .regular
        table.dataSource = self; table.delegate = self
        table.onKey = { [weak self] in self?.handleKey($0) == true }
        table.onHoverChange = { [weak self] in self?.updatePreviewShortcut() }
        table.target = self; table.action = #selector(copyClicked)
        table.setAccessibilityLabel("Clipboard history")
        let scroll = historyScroll; scroll.documentView = table; scroll.hasVerticalScroller = true; scroll.drawsBackground = false
        add(scroll, to: stack)
        scroll.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(updatePreviewShortcut), name: NSView.boundsDidChangeNotification, object: scroll.contentView)
        emptyRows.orientation = .vertical; emptyRows.alignment = .leading; emptyRows.spacing = 8
        for text in ["Copies appear here.", "Click to copy it again.", "Preview image with hover + space"] {
            let label = NSTextField(wrappingLabelWithString: text)
            label.font = .systemFont(ofSize: 12)
            label.preferredMaxLayoutWidth = 236
            add(label, to: emptyRows)
        }
        tutorialCard.boxType = .custom; tutorialCard.titlePosition = .noTitle; tutorialCard.borderWidth = 0
        tutorialCard.cornerRadius = 8; tutorialCard.fillColor = .quaternaryLabelColor
        tutorialCard.contentViewMargins = NSSize(width: 12, height: 10)
        tutorialCard.contentView = emptyRows
        tutorialCard.heightAnchor.constraint(equalToConstant: 96).isActive = true
        for view in [tutorialCard, emptyLabel] {
            view.translatesAutoresizingMaskIntoConstraints = false
            emptyState.addSubview(view)
            NSLayoutConstraint.activate([view.leadingAnchor.constraint(equalTo: emptyState.leadingAnchor), view.trailingAnchor.constraint(equalTo: emptyState.trailingAnchor), view.topAnchor.constraint(equalTo: emptyState.topAnchor)])
        }
        emptyLabel.font = .systemFont(ofSize: 13)
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.heightAnchor.constraint(equalToConstant: 30).isActive = true
        add(emptyState, to: stack)
        emptyState.isHidden = true

    }

    private func add(_ view: NSView, to stack: NSStackView) {
        stack.addArrangedSubview(view)
        view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }

    private func makeRow(icon: NSImage?, title: NSTextField, shortcut: String? = nil) -> NSStackView {
        let image = NSImageView(); image.image = icon; image.imageScaling = .scaleProportionallyUpOrDown
        image.widthAnchor.constraint(equalToConstant: 22).isActive = true; image.heightAnchor.constraint(equalToConstant: 22).isActive = true
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        title.lineBreakMode = .byTruncatingTail; title.font = .systemFont(ofSize: 13, weight: .medium)
        title.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let cell = NSStackView(views: [image, title]); cell.spacing = 8; cell.edgeInsets = NSEdgeInsets(top: 4, left: 6, bottom: 4, right: 6)
        if let shortcut {
            let key = NSTextField(labelWithString: shortcut)
            key.font = .systemFont(ofSize: 11); key.textColor = .secondaryLabelColor
            key.setContentHuggingPriority(.required, for: .horizontal)
            key.setContentCompressionResistancePriority(.required, for: .horizontal)
            cell.addArrangedSubview(key)
            key.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6).isActive = true
        } else { title.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6).isActive = true }
        return cell
    }

    private func configureMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: "Clipboard")
        statusItem.button?.image?.isTemplate = true
        clipboardMenu.delegate = self
        clipboardMenu.autoenablesItems = false
        let clipboard = NSMenuItem()
        clipboard.view = content
        clipboardMenu.addItem(clipboard)
        clipboardMenu.addItem(.separator())
        let clearMenu = NSMenu()
        clearMenu.autoenablesItems = false
        clearNowItem.target = self; clearNowItem.action = #selector(clearHistory)
        clearNowItem.isEnabled = false
        clearMenu.addItem(clearNowItem)
        clearMenu.addItem(.separator())
        for (title, minutes) in [("Every 30 Minutes", 30), ("Every 8 Hours", 480), ("Every 7 Days", 10080)] {
            let item = NSMenuItem(title: title, action: #selector(changeRetention(_:)), keyEquivalent: "")
            item.target = self; item.tag = minutes; item.state = minutes == 10080 ? .on : .off
            clearMenu.addItem(item); retentionItems.append(item)
        }
        clearItem.submenu = clearMenu
        clearItem.isEnabled = false
        clipboardMenu.addItem(clearItem)
        clipboardMenu.addItem(withTitle: "Quit Clipboard", action: #selector(quit), keyEquivalent: "q").target = self
        for index in 0..<9 {
            let item = NSMenuItem(title: "Copy item \(index + 1)", action: #selector(copyNumbered(_:)), keyEquivalent: "\(index + 1)")
            item.target = self; item.tag = index; item.keyEquivalentModifierMask = .command
            item.isHidden = true; item.allowsKeyEquivalentWhenHidden = true; item.isEnabled = false
            clipboardMenu.addItem(item); copyItems.append(item)
        }
        previewItem.target = self; previewItem.action = #selector(previewClip(_:))
        previewItem.keyEquivalentModifierMask = []
        previewItem.isHidden = true; previewItem.allowsKeyEquivalentWhenHidden = true; previewItem.isEnabled = false
        clipboardMenu.addItem(previewItem)
        statusItem.menu = clipboardMenu
        let menu = NSMenu()
        let appItem = NSMenuItem(); let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Clipboard", action: #selector(quit), keyEquivalent: "q").target = self
        appItem.submenu = appMenu; menu.addItem(appItem)
        let edit = NSMenuItem(); let editMenu = NSMenu(title: "Edit")
        for (name, action, key) in [("Undo", "undo:", "z"), ("Cut", "cut:", "x"), ("Copy", "copy:", "c"), ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")] { editMenu.addItem(NSMenuItem(title: name, action: Selector(action), keyEquivalent: key)) }
        edit.submenu = editMenu; menu.addItem(edit); NSApp.mainMenu = menu
    }

    func tableViewSelectionDidChange(_ notification: Notification) { updatePreviewShortcut() }
    @objc private func updatePreviewShortcut() {
        let clip = hovered ?? selected
        previewItem.isEnabled = !search.isSearching && clip?.canPreview == true
        previewItem.representedObject = clip
    }
    @objc private func previewClip(_ sender: NSMenuItem) {
        guard let clip = sender.representedObject as? Clip else { return }
        dismiss(); onPreview?(clip)
    }
    private var selected: Clip? { filtered.indices.contains(table.selectedRow) ? filtered[table.selectedRow] : nil }
    private var hovered: Clip? { filtered.indices.contains(table.hoveredRow) ? filtered[table.hoveredRow] : nil }
    func numberOfRows(in tableView: NSTableView) -> Int { filtered.count }
    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? { ClipboardRow() }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let clip = filtered[row]
        let icon: NSImage?
        if clip.kind == .image, let thumb = clip.thumbnail?.split(separator: ",", maxSplits: 1).last, let data = Data(base64Encoded: String(thumb)) { icon = NSImage(data: data) }
        else if let id = clip.sourceAppId {
            if let cached = iconCache[id] { icon = cached }
            else if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) { let image = NSWorkspace.shared.icon(forFile: url.path); iconCache[id] = image; icon = image }
            else { icon = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: nil) }
        } else { icon = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: nil) }
        let summary = String(clip.summary.prefix(180)).replacingOccurrences(of: "\n", with: " ")
        let cell = makeRow(icon: icon, title: NSTextField(labelWithString: summary), shortcut: row < 9 ? "⌘\(row + 1)" : nil)
        cell.toolTip = "\(clip.appName) · ⌘C Copy" + (clip.canPreview ? " · Space Preview" : "")
        cell.setAccessibilityElement(true); cell.setAccessibilityLabel("\(summary), \(clip.appName), \(clip.kind.rawValue)")
        return cell
    }
    private func updateContentSize() {
        let showEmpty = historyAvailable == true && filtered.isEmpty
        emptyState.isHidden = !showEmpty
        tutorialCard.isHidden = !clips.isEmpty
        emptyLabel.isHidden = clips.isEmpty
        historyScroll.isHidden = showEmpty || (filtered.isEmpty && !searchExpanded)
        let bodyHeight = showEmpty ? (clips.isEmpty ? 96.0 : 30.0) : CGFloat(filtered.count) * (table.rowHeight + table.intercellSpacing.height)
        let naturalHeight = 20 + 26 + (bodyHeight > 0 ? 8 + bodyHeight : 0)
        let height = searchExpanded ? 236 : min(236, naturalHeight)
        guard content.frame.height != height else { return }
        table.clearHover()
        content.setFrameSize(NSSize(width: content.frame.width, height: height))
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        guard menuOpen else { return false }
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        if event.keyCode == 53 { dismiss(); return true }
        if modifiers == .command, event.charactersIgnoringModifiers == "f" { search.focus(); return true }
        if modifiers == .command, event.charactersIgnoringModifiers == "c" {
            if let hovered { onCopy?(hovered, false); return true }
            if search.isSearching { return false }
            if let selected { onCopy?(selected, false) }
            return true
        }
        if event.keyCode == 36, modifiers.isEmpty { pasteClip(); return true }
        if [125, 126].contains(event.keyCode), modifiers.isEmpty { moveSelection(by: event.keyCode == 125 ? 1 : -1); return true }
        return false
    }
    @objc private func copyNumbered(_ sender: NSMenuItem) {
        guard filtered.indices.contains(sender.tag) else { return }
        onCopy?(filtered[sender.tag], false)
    }
    @objc private func copyClicked() {
        guard filtered.indices.contains(table.clickedRow) else { return }
        onCopy?(filtered[table.clickedRow], false)
    }
    @objc private func pasteClip() { if let selected { onCopy?(selected, true) } }
    @objc private func clearHistory() { onClear?() }
    @objc private func changeRetention(_ sender: NSMenuItem) { onRetentionChange?(Double(sender.tag) / 1440) }
    @objc private func quit() { NSApp.terminate(nil) }
}
