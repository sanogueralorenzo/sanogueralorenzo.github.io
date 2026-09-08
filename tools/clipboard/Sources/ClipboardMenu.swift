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

final class ClipboardItemView: NSStackView {
    let imageView = NSImageView()
    let titleField = NSTextField(labelWithString: "")
    let shortcutField = NSTextField(labelWithString: "")
    private var titleTrailing: NSLayoutConstraint!
    private var shortcutTrailing: NSLayoutConstraint!

    init() {
        super.init(frame: .zero)
        let title = titleField
        imageView.wantsLayer = true
        imageView.layer?.masksToBounds = true
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.widthAnchor.constraint(equalToConstant: 26).isActive = true
        imageView.heightAnchor.constraint(equalToConstant: 26).isActive = true
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        title.setContentHuggingPriority(.defaultLow, for: .horizontal)
        title.lineBreakMode = .byTruncatingTail; title.font = .systemFont(ofSize: 13, weight: .medium)
        shortcutField.font = .systemFont(ofSize: 11); shortcutField.textColor = .secondaryLabelColor
        shortcutField.setContentHuggingPriority(.required, for: .horizontal)
        shortcutField.setContentCompressionResistancePriority(.required, for: .horizontal)
        for view in [imageView, title, shortcutField] { addArrangedSubview(view) }
        spacing = 8; edgeInsets = NSEdgeInsets(top: 2, left: 6, bottom: 2, right: 6)
        titleTrailing = title.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6)
        shortcutTrailing = shortcutField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6)
        setShortcut(nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setShortcut(_ shortcut: String?) {
        titleTrailing.isActive = false; shortcutTrailing.isActive = false
        shortcutField.stringValue = shortcut ?? ""
        shortcutField.isHidden = shortcut == nil
        (shortcut == nil ? titleTrailing : shortcutTrailing)?.isActive = true
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
    var onCopy: ((Clip) -> Void)?
    var onSpace: ((Clip) -> Void)?
    var onClear: (() -> Void)?
    var onRetentionChange: ((Double) -> Void)?
    private let clipboardMenu = NSMenu()
    private let content = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 240))
    private let search = ClipboardSearch()
    private let table = ClipboardTable()
    private let historyScroll = NSScrollView()
    private let emptyState = NSView()
    private let emptyLabel = NSTextField(labelWithString: "No matching clips")
    private let emptyRows = NSStackView()
    private let clearItem = NSMenuItem(title: "Clear", action: nil, keyEquivalent: "")
    private let clearNowItem = NSMenuItem(title: "Now", action: nil, keyEquivalent: "")
    private var retentionItems: [NSMenuItem] = []
    private var statusItem: NSStatusItem!
    private let spaceItem = NSMenuItem(title: "Open or Preview", action: nil, keyEquivalent: " ")
    private var copyItems: [NSMenuItem] = []
    private var clips: [Clip] = []
    private var filtered: [Clip] = []
    private var iconCache: [String: NSImage] = [:]
    private lazy var browserIds = NSWorkspace.shared.urlsForApplications(toOpen: URL(string: "https://example.com")!).compactMap { Bundle(url: $0)?.bundleIdentifier }
    private let thumbnailCache = NSCache<NSString, NSImage>()
    private let websiteIcons = ClipboardWebsiteIcons()
    private var menuOpen = false

    override init() {
        super.init(); thumbnailCache.countLimit = 200; configureContent(); configureMenu(); report(nil)
        websiteIcons.onChange = { [weak self] origin in
            guard let self, menuOpen else { return }
            for (row, clip) in filtered.enumerated() {
                guard let url = clip.webURL, ClipboardWebsiteIcons.origin(for: url) == origin,
                      let cell = table.view(atColumn: 0, row: row, makeIfNecessary: false) as? ClipboardItemView else { continue }
                cell.imageView.image = icon(for: clip)
            }
        }
    }
    func update(clips: [Clip], retentionDays: Double?) {
        self.clips = clips
        clearNowItem.isEnabled = !clips.isEmpty
        for item in retentionItems { item.state = retentionDays == Double(item.tag) / 1440 ? .on : .off }
        if clips.isEmpty { thumbnailCache.removeAllObjects(); websiteIcons.clear() }
        if menuOpen { reload() }
    }
    func report(_ error: String?) { statusItem.button?.toolTip = error ?? "Clipboard · ⌥⇧V" }
    func toggle() { menuOpen ? dismiss() : show() }
    func show() { if !menuOpen { statusItem.button?.performClick(nil) } }
    func dismiss() { clipboardMenu.cancelTracking() }
    func menuWillOpen(_ menu: NSMenu) {
        menuOpen = true; onOpen?()
        search.endSearch(); search.stringValue = ""
        table.clearHover(); table.deselectAll(nil); reload()
    }
    func menuDidClose(_ menu: NSMenu) { menuOpen = false; search.endSearch() }
    func controlTextDidEndEditing(_ obj: Notification) { search.endSearch(); updateSpaceShortcut() }
    func controlTextDidChange(_ obj: Notification) { reload() }
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.moveDown(_:)): moveSelection(by: 1)
        case #selector(NSResponder.moveUp(_:)): moveSelection(by: -1)
        case #selector(NSResponder.cancelOperation(_:)): dismiss()
        default: return false
        }
        return true
    }
    private func moveSelection(by offset: Int) {
        guard !filtered.isEmpty else { return }
        let row = max(0, min(filtered.count - 1, table.selectedRow + offset))
        table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        table.scrollRowToVisible(row); search.endSearch(); content.window?.makeFirstResponder(table); updateSpaceShortcut()
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
        updateContentSize(); updateSpaceShortcut()
    }
    private func configureContent() {
        let root = content
        let stack = NSStackView()
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 10), stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -10), stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 10), stack.bottomAnchor.constraint(equalTo: root.bottomAnchor)])
        let title = NSTextField(labelWithString: "Clipboard")
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        let shortcut = NSTextField(labelWithString: "Open ⌥⇧V")
        shortcut.font = .systemFont(ofSize: 11)
        shortcut.textColor = .secondaryLabelColor
        shortcut.setAccessibilityLabel("Open Clipboard with Option Shift V")
        let header = NSStackView(views: [title, NSView(), shortcut])
        header.orientation = .horizontal; header.alignment = .centerY
        add(header, to: stack)
        header.heightAnchor.constraint(equalToConstant: 20).isActive = true
        search.placeholderString = "Search"
        search.delegate = self
        search.didFocus = { [weak self] in self?.updateSpaceShortcut() }
        search.sendsSearchStringImmediately = true
        search.font = .systemFont(ofSize: 13)
        search.setAccessibilityLabel("Search clips or apps")
        add(search, to: stack)
        search.heightAnchor.constraint(equalToConstant: 30).isActive = true
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("clip")); column.width = content.frame.width - 22
        table.addTableColumn(column)
        table.headerView = nil; table.backgroundColor = .clear
        table.rowHeight = 30; table.intercellSpacing = NSSize(width: 0, height: 2)
        table.style = .plain; table.selectionHighlightStyle = .regular
        table.dataSource = self; table.delegate = self
        table.onKey = { [weak self] in self?.handleKey($0) == true }
        table.onHoverChange = { [weak self] in self?.updateSpaceShortcut() }
        table.target = self; table.action = #selector(copyClicked)
        table.setAccessibilityLabel("Clipboard history")
        let scroll = historyScroll; scroll.documentView = table; scroll.hasVerticalScroller = true; scroll.drawsBackground = false
        add(scroll, to: stack)
        scroll.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(updateSpaceShortcut), name: NSView.boundsDidChangeNotification, object: scroll.contentView)
        emptyRows.orientation = .vertical; emptyRows.alignment = .centerX; emptyRows.spacing = 4
        emptyRows.edgeInsets = NSEdgeInsets(top: 12, left: 4, bottom: 12, right: 4)
        for (index, text) in ["Clipboard History", "Copy something to get started.", "Preview image with hover + space."].enumerated() {
            let label = NSTextField(wrappingLabelWithString: text)
            label.font = .systemFont(ofSize: 12, weight: index == 0 ? .medium : .regular)
            label.textColor = index == 0 ? .labelColor : .secondaryLabelColor
            label.alignment = .center
            label.preferredMaxLayoutWidth = 252
            emptyRows.addArrangedSubview(label)
            label.widthAnchor.constraint(equalTo: emptyRows.widthAnchor, constant: -8).isActive = true
            if index == 0 { emptyRows.setCustomSpacing(10, after: label) }
        }
        for view in [emptyRows, emptyLabel] {
            view.translatesAutoresizingMaskIntoConstraints = false
            emptyState.addSubview(view)
            NSLayoutConstraint.activate([view.leadingAnchor.constraint(equalTo: emptyState.leadingAnchor), view.trailingAnchor.constraint(equalTo: emptyState.trailingAnchor), view.topAnchor.constraint(equalTo: emptyState.topAnchor)])
        }
        emptyLabel.font = .systemFont(ofSize: 13)
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.alignment = .center
        emptyLabel.heightAnchor.constraint(equalToConstant: 30).isActive = true
        add(emptyState, to: stack)
        emptyState.isHidden = true

    }

    private func add(_ view: NSView, to stack: NSStackView) {
        stack.addArrangedSubview(view)
        view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
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
        for (title, minutes) in [("After 30 Minutes", 30), ("After 8 Hours", 480), ("After 7 Days", 10080)] {
            let item = NSMenuItem(title: title, action: #selector(changeRetention(_:)), keyEquivalent: "")
            item.target = self; item.tag = minutes; item.state = minutes == 10080 ? .on : .off
            clearMenu.addItem(item); retentionItems.append(item)
        }
        clearItem.submenu = clearMenu
        clipboardMenu.addItem(clearItem)
        clipboardMenu.addItem(withTitle: "Quit", action: #selector(quit), keyEquivalent: "q").target = self
        for index in 0..<9 {
            let item = NSMenuItem(title: "Copy item \(index + 1)", action: #selector(copyNumbered(_:)), keyEquivalent: "\(index + 1)")
            item.target = self; item.tag = index; item.keyEquivalentModifierMask = .command
            item.isHidden = true; item.allowsKeyEquivalentWhenHidden = true; item.isEnabled = false
            clipboardMenu.addItem(item); copyItems.append(item)
        }
        spaceItem.target = self; spaceItem.action = #selector(performSpaceAction(_:))
        spaceItem.keyEquivalentModifierMask = []
        spaceItem.isHidden = true; spaceItem.allowsKeyEquivalentWhenHidden = true; spaceItem.isEnabled = false
        clipboardMenu.addItem(spaceItem)
        statusItem.menu = clipboardMenu
        let menu = NSMenu()
        let appItem = NSMenuItem(); let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit", action: #selector(quit), keyEquivalent: "q").target = self
        appItem.submenu = appMenu; menu.addItem(appItem)
        let edit = NSMenuItem(); let editMenu = NSMenu(title: "Edit")
        for (name, action, key) in [("Undo", "undo:", "z"), ("Cut", "cut:", "x"), ("Copy", "copy:", "c"), ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")] { editMenu.addItem(NSMenuItem(title: name, action: Selector(action), keyEquivalent: key)) }
        edit.submenu = editMenu; menu.addItem(edit); NSApp.mainMenu = menu
    }

    func tableViewSelectionDidChange(_ notification: Notification) { updateSpaceShortcut() }
    @objc private func updateSpaceShortcut() {
        let clip = hovered ?? selected
        spaceItem.isEnabled = !search.isSearching && clip?.spaceHint != nil
        spaceItem.representedObject = clip
    }
    @objc private func performSpaceAction(_ sender: NSMenuItem) {
        guard let clip = sender.representedObject as? Clip else { return }
        dismiss(); onSpace?(clip)
    }
    private var selected: Clip? { filtered.indices.contains(table.selectedRow) ? filtered[table.selectedRow] : nil }
    private var hovered: Clip? { filtered.indices.contains(table.hoveredRow) ? filtered[table.hoveredRow] : nil }
    func numberOfRows(in tableView: NSTableView) -> Int { filtered.count }
    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let identifier = NSUserInterfaceItemIdentifier("ClipboardRow")
        let view = tableView.makeView(withIdentifier: identifier, owner: self) as? ClipboardRow ?? ClipboardRow()
        view.identifier = identifier
        return view
    }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let clip = filtered[row]
        let summary = String(clip.summary.prefix(180)).replacingOccurrences(of: "\n", with: " ")
        let identifier = NSUserInterfaceItemIdentifier("ClipboardItem")
        let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? ClipboardItemView ?? ClipboardItemView()
        cell.identifier = identifier
        cell.imageView.layer?.cornerRadius = clip.kind == .image ? 4 : 0
        cell.imageView.image = icon(for: clip)
        cell.titleField.stringValue = summary
        cell.setShortcut(row < 9 ? "⌘\(row + 1)" : nil)
        cell.toolTip = clip.spaceHint
        cell.setAccessibilityElement(true); cell.setAccessibilityLabel("\(summary), \(clip.appName), \(clip.kind.rawValue)")
        return cell
    }
    private func icon(for clip: Clip) -> NSImage? {
        if let url = clip.webURL {
            if let image = websiteIcons.image(for: url) { return image }
            let browserId = clip.sourceAppId.flatMap { browserIds.contains($0) ? $0 : nil } ?? browserIds.first
            if let browserId, let image = appIcon(for: browserId) {
                return image
            }
        }
        if clip.kind == .image, let thumbnail = clip.thumbnail {
            if let cached = thumbnailCache.object(forKey: thumbnail as NSString) { return cached }
            guard let thumb = thumbnail.split(separator: ",", maxSplits: 1).last,
                  let data = Data(base64Encoded: String(thumb)),
                  let source = NSImage(data: data)?.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
            let side = min(source.width, source.height)
            let rect = CGRect(x: (source.width - side) / 2, y: (source.height - side) / 2, width: side, height: side)
            guard let cropped = source.cropping(to: rect) else { return nil }
            let image = NSImage(cgImage: cropped, size: .zero)
            thumbnailCache.setObject(image, forKey: thumbnail as NSString)
            return image
        }
        return clip.sourceAppId.flatMap { appIcon(for: $0) } ?? NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: nil)
    }

    private func appIcon(for id: String) -> NSImage? {
        if let cached = iconCache[id] { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return nil }
        let image = NSWorkspace.shared.icon(forFile: url.path)
        iconCache[id] = image
        return image
    }

    private func updateContentSize() {
        let showEmpty = filtered.isEmpty
        emptyState.isHidden = !showEmpty
        emptyRows.isHidden = !clips.isEmpty
        emptyLabel.isHidden = clips.isEmpty
        historyScroll.isHidden = showEmpty
        let bodyHeight = showEmpty ? (clips.isEmpty ? emptyRows.fittingSize.height : 30.0) : CGFloat(min(filtered.count, 6)) * (table.rowHeight + table.intercellSpacing.height)
        let height = 10 + 20 + 8 + 30 + 8 + bodyHeight
        guard content.frame.height != height else { return }
        table.clearHover()
        content.setFrameSize(NSSize(width: content.frame.width, height: height))
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        guard menuOpen else { return false }
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        if event.keyCode == 53 { dismiss(); return true }
        if modifiers == .command, event.charactersIgnoringModifiers == "c" {
            if let hovered { onCopy?(hovered); return true }
            if search.isSearching { return false }
            if let selected { onCopy?(selected) }
            return true
        }
        if [125, 126].contains(event.keyCode), modifiers.isEmpty { moveSelection(by: event.keyCode == 125 ? 1 : -1); return true }
        return false
    }
    @objc private func copyNumbered(_ sender: NSMenuItem) {
        guard filtered.indices.contains(sender.tag) else { return }
        onCopy?(filtered[sender.tag])
    }
    @objc private func copyClicked() {
        guard filtered.indices.contains(table.clickedRow) else { return }
        onCopy?(filtered[table.clickedRow])
    }
    @objc private func clearHistory() { onClear?() }
    @objc private func changeRetention(_ sender: NSMenuItem) { onRetentionChange?(Double(sender.tag) / 1440) }
    @objc private func quit() { NSApp.terminate(nil) }
}
