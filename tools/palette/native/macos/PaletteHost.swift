import AppKit
import Carbon.HIToolbox
import ApplicationServices

final class ClipboardPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class ClipboardRow: NSTableRowView {
    override func drawSelection(in dirtyRect: NSRect) {
        NSColor(calibratedRed: 0.64, green: 0.54, blue: 0.84, alpha: 0.24).setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 0), xRadius: 8, yRadius: 8).fill()
    }
}

final class ClipboardTable: NSTableView {
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
        let tracking = NSTrackingArea(rect: .zero, options: [.inVisibleRect, .activeInKeyWindow, .mouseMoved, .mouseEnteredAndExited], owner: self)
        addTrackingArea(tracking); hoverTracking = tracking
    }
    override func mouseMoved(with event: NSEvent) {
        hoverPoint = event.locationInWindow
        if hoveredRow >= 0 { selectRowIndexes(IndexSet(integer: hoveredRow), byExtendingSelection: false) }
    }
    override func mouseEntered(with event: NSEvent) { mouseMoved(with: event) }
    override func mouseExited(with event: NSEvent) { hoverPoint = nil }
    override func mouseDown(with event: NSEvent) { mouseMoved(with: event); super.mouseDown(with: event) }
    func clearHover() { hoverPoint = nil }
}

@main
@MainActor
final class PaletteAppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate, NSMenuItemValidation {
    private let panel = ClipboardPanel(contentRect: NSRect(x: 0, y: 0, width: 340, height: 300), styleMask: [.borderless], backing: .buffered, defer: false)
    private let search = NSSearchField()
    private let table = ClipboardTable()
    private let historyScroll = NSScrollView()
    private let preview = NSScrollView()
    private let previewText = NSTextView()
    private let previewImage = NSImageView()
    private var statusItem: NSStatusItem!
    private var settingsPanel: SettingsPanel?
    private var store: ClipboardStore!
    private var clips: [Clip] = []
    private var filtered: [Clip] = []
    private var policy = ClipboardPolicy()
    private var previousApp: NSRunningApplication?
    private var timer: Timer?
    private var activationObserver: NSObjectProtocol?
    private var keyMonitor: Any?
    private var shortcutRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var changeCount = NSPasteboard.general.changeCount
    private var iconCache: [String: NSImage] = [:]
    private var previewVisible = false
    private let more = NSButton()
    private var issue: String?
    private var shortcutError: String?
    private var historyAvailable: Bool?
    private let accent = NSColor(calibratedRed: 0.75, green: 0.69, blue: 0.9, alpha: 1)

    static func main() {
        let app = NSApplication.shared
        let delegate = PaletteAppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        configurePanel()
        configureMenu()
        installShortcut()
        let standard = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Palette")
        let args = CommandLine.arguments
        let review = args.contains("--review")
        var directory = standard
        if review {
            guard let index = args.firstIndex(of: "--data-dir"), args.indices.contains(index + 1), args[index + 1].hasPrefix("/") else {
                report("Review mode requires --data-dir /absolute/path to a separate profile."); show(); return
            }
            directory = URL(fileURLWithPath: args[index + 1])
            guard directory.resolvingSymlinksInPath().standardizedFileURL != standard.resolvingSymlinksInPath().standardizedFileURL else {
                report("Review mode requires a separate profile."); show(); return
            }
        }
        store = ClipboardStore(directory: directory, review: review)
        policy.enabled = false
        store.onChange = { [weak self] clips, policy, error, available in
            guard let self else { return }
            self.clips = clips; self.policy = policy; self.historyAvailable = available
            self.report(error ?? self.issue ?? self.shortcutError)
            self.reload()
        }
        store.load()
        timer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.capture() } }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didDeactivateApplicationNotification, object: nil, queue: .main) { [weak self] notification in
            MainActor.assumeIsolated { self?.capture(source: notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication) }
        }
        if !args.contains("--background") { show() }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { if !panel.isVisible { show() }; return true }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) {
        capture()
        store?.finishWrites()
        timer?.invalidate()
        if let shortcutRef { UnregisterEventHotKey(shortcutRef) }
        if let eventHandlerRef { RemoveEventHandler(eventHandlerRef) }
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        if let activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(activationObserver) }
    }

    private func configurePanel() {
        panel.title = "Palette"
        panel.delegate = self
        panel.level = .floating
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .transient]
        panel.isReleasedWhenClosed = false
        panel.hasShadow = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.appearance = NSAppearance(named: .darkAqua)
        let root = NSView()
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor(calibratedRed: 0.105, green: 0.098, blue: 0.12, alpha: 1).cgColor
        root.layer?.cornerRadius = 16
        root.layer?.borderWidth = 1
        root.layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
        panel.contentView = root
        let stack = NSStackView()
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 10), stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -10), stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 10), stack.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -10)])
        let mark = NSImageView(image: NSImage(systemSymbolName: "square.on.square", accessibilityDescription: "Palette")!)
        mark.contentTintColor = accent
        mark.widthAnchor.constraint(equalToConstant: 18).isActive = true
        let title = NSTextField(labelWithString: "Palette")
        title.font = .systemFont(ofSize: 14, weight: .semibold)
        more.image = NSImage(systemSymbolName: "ellipsis", accessibilityDescription: "More")
        more.target = self; more.action = #selector(openMenu(_:))
        more.isBordered = false
        more.setAccessibilityLabel("More")
        let heading = NSStackView(views: [mark, title, NSView(), more]); heading.spacing = 8
        add(heading, to: stack)
        search.placeholderString = "Search clips or apps"
        search.delegate = self
        search.sendsSearchStringImmediately = true
        search.font = .systemFont(ofSize: 13)
        search.setAccessibilityLabel("Search clips or apps")
        add(search, to: stack)
        search.heightAnchor.constraint(equalToConstant: 26).isActive = true
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("clip")); column.width = 318
        table.addTableColumn(column)
        table.headerView = nil; table.backgroundColor = .clear
        table.rowHeight = 30; table.intercellSpacing = NSSize(width: 0, height: 2)
        table.style = .plain; table.selectionHighlightStyle = .regular
        table.dataSource = self; table.delegate = self
        table.target = self; table.doubleAction = #selector(pasteClip)
        table.setAccessibilityLabel("Clipboard history")
        let context = NSMenu()
        context.addItem(withTitle: "Pin / Unpin", action: #selector(pinContextClip), keyEquivalent: "").target = self
        context.addItem(withTitle: "Delete", action: #selector(deleteClip), keyEquivalent: "") .target = self
        table.menu = context
        let scroll = historyScroll; scroll.documentView = table; scroll.hasVerticalScroller = true; scroll.drawsBackground = false
        add(scroll, to: stack)
        scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 100).isActive = true
        preview.documentView = previewText; preview.hasVerticalScroller = true; preview.drawsBackground = false
        previewText.isEditable = false; previewText.isSelectable = true; previewText.drawsBackground = false
        previewText.font = .systemFont(ofSize: 13); previewText.textColor = .labelColor
        previewText.textContainerInset = NSSize(width: 8, height: 8)
        previewText.autoresizingMask = [.width]; previewText.textContainer?.widthTracksTextView = true
        add(preview, to: stack); preview.heightAnchor.constraint(greaterThanOrEqualToConstant: 100).isActive = true; preview.isHidden = true
        previewImage.imageScaling = .scaleProportionallyUpOrDown
        previewImage.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        previewImage.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        add(previewImage, to: stack); previewImage.heightAnchor.constraint(greaterThanOrEqualToConstant: 100).isActive = true; previewImage.isHidden = true
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let handled = MainActor.assumeIsolated { self?.handleKey(event) == true }
            return handled ? nil : event
        }
    }

    private func add(_ view: NSView, to stack: NSStackView) {
        stack.addArrangedSubview(view)
        view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }

    private func configureMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "square.on.square", accessibilityDescription: "Palette")
        statusItem.button?.image?.isTemplate = true
        statusItem.button?.target = self; statusItem.button?.action = #selector(toggle)
        let menu = NSMenu()
        let appItem = NSMenuItem(); let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
        appMenu.addItem(withTitle: "Quit Palette", action: #selector(quit), keyEquivalent: "q").target = self
        appItem.submenu = appMenu; menu.addItem(appItem)
        let edit = NSMenuItem(); let editMenu = NSMenu(title: "Edit")
        for (name, action, key) in [("Undo", "undo:", "z"), ("Cut", "cut:", "x"), ("Copy", "copy:", "c"), ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")] { editMenu.addItem(NSMenuItem(title: name, action: Selector(action), keyEquivalent: key)) }
        edit.submenu = editMenu; menu.addItem(edit); NSApp.mainMenu = menu
    }

    @objc private func toggle() { panel.isVisible ? dismiss() : show() }
    private func show() {
        store?.prune()
        if let front = NSWorkspace.shared.frontmostApplication, front.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            capture(source: front)
            previousApp = front
        }
        guard let button = statusItem.button, let window = button.window, let screen = window.screen else { return }
        let anchor = window.convertToScreen(button.convert(button.bounds, to: nil))
        let frame = screen.visibleFrame
        // A hidden menu-bar item can have an offscreen frame. Keep shortcut access visible.
        let preferredX = anchor.midY >= frame.maxY ? anchor.maxX - panel.frame.width : frame.maxX - panel.frame.width - 8
        let x = min(max(preferredX, frame.minX + 8), frame.maxX - panel.frame.width - 8)
        panel.setFrameOrigin(NSPoint(x: x, y: frame.maxY - panel.frame.height - 6))
        search.stringValue = ""; previewVisible = false; table.clearHover(); table.deselectAll(nil); reload()
        NSApp.activate(ignoringOtherApps: true); panel.makeKeyAndOrderFront(nil); panel.makeFirstResponder(table)
    }
    private func dismiss(restoreFocus: Bool = true) {
        panel.orderOut(nil)
        if restoreFocus { previousApp?.activate(options: []) }
        previousApp = nil
    }
    func windowDidResignKey(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.panel.isKeyWindow, self.panel.attachedSheet == nil else { return }
            self.dismiss(restoreFocus: false)
        }
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool { dismiss(); return false }

    private func capture(source: NSRunningApplication? = nil) {
        guard let store else { return }
        let pb = NSPasteboard.general
        guard pb.changeCount != changeCount else { return }
        changeCount = pb.changeCount
        let source = source ?? NSWorkspace.shared.frontmostApplication
        guard policy.enabled, source?.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              !policy.excludedAppIds.contains(source?.bundleIdentifier ?? "") else { return }
        do {
            guard let item = try ClipboardSupport.capture(pb, source: source, ignoreSensitive: true) else { return }
            let clip = try JSONDecoder().decode(Clip.self, from: JSONSerialization.data(withJSONObject: item))
            store.capture(clip)
        } catch { report(error.localizedDescription) }
    }

    func controlTextDidChange(_ obj: Notification) { previewVisible = false; reload() }
    private func reload() {
        let id = selected?.id
        let query = search.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        filtered = clips.filter { clip in
            query.isEmpty || [clip.content, clip.title ?? "", clip.appName].contains { $0.localizedCaseInsensitiveContains(query) }
        }
        table.reloadData()
        if !filtered.isEmpty { table.selectRowIndexes(IndexSet(integer: filtered.firstIndex { $0.id == id } ?? 0), byExtendingSelection: false) }
        updatePreview()
    }
    private var selected: Clip? { filtered.indices.contains(table.selectedRow) ? filtered[table.selectedRow] : nil }
    private var hovered: Clip? { !previewVisible && filtered.indices.contains(table.hoveredRow) ? filtered[table.hoveredRow] : nil }
    private var contextClip: Clip? { filtered.indices.contains(table.clickedRow) ? filtered[table.clickedRow] : selected }
    func numberOfRows(in tableView: NSTableView) -> Int { filtered.count }
    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? { ClipboardRow() }
    func tableViewSelectionDidChange(_ notification: Notification) { updatePreview() }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let clip = filtered[row]
        let icon: NSImage?
        if clip.kind == .image, let thumb = clip.thumbnail?.split(separator: ",", maxSplits: 1).last, let data = Data(base64Encoded: String(thumb)) { icon = NSImage(data: data) }
        else if let id = clip.sourceAppId {
            if let cached = iconCache[id] { icon = cached }
            else if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) { let image = NSWorkspace.shared.icon(forFile: url.path); iconCache[id] = image; icon = image }
            else { icon = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: nil) }
        } else { icon = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: nil) }
        let image = NSImageView(); image.image = icon; image.imageScaling = .scaleProportionallyUpOrDown
        image.widthAnchor.constraint(equalToConstant: 22).isActive = true; image.heightAnchor.constraint(equalToConstant: 22).isActive = true
        let summary = String(clip.summary.prefix(180)).replacingOccurrences(of: "\n", with: " ")
        let title = NSTextField(labelWithString: (clip.pinned ? "★ " : "") + summary)
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        title.lineBreakMode = .byTruncatingTail; title.font = .systemFont(ofSize: 13, weight: .medium)
        title.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let cell = NSStackView(views: [image, title]); cell.spacing = 8; cell.edgeInsets = NSEdgeInsets(top: 4, left: 6, bottom: 4, right: 6)
        title.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6).isActive = true
        cell.toolTip = "\(clip.appName) · ⌘C to copy · Space to preview"
        cell.setAccessibilityElement(true); cell.setAccessibilityLabel("\(summary), \(clip.appName), \(clip.kind.rawValue)\(clip.pinned ? ", pinned" : "")")
        return cell
    }
    private func updatePreview() {
        preview.isHidden = true; previewImage.isHidden = true; historyScroll.isHidden = false
        guard previewVisible, let clip = selected else { return }
        historyScroll.isHidden = true
        if clip.kind == .image, let thumb = clip.thumbnail?.split(separator: ",", maxSplits: 1).last, let data = Data(base64Encoded: String(thumb)) {
            previewImage.image = NSImage(data: data); previewImage.setAccessibilityLabel(clip.summary); previewImage.isHidden = false
        } else {
            previewText.string = clip.content
            previewText.frame.size.width = 318
            preview.isHidden = false
            previewText.scrollToBeginningOfDocument(nil)
        }
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        guard panel.isKeyWindow, panel.attachedSheet == nil else { return false }
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        let editingSearch = panel.firstResponder === search.currentEditor()
        if event.keyCode == 53 { dismiss(); return true }
        if modifiers.contains(.command), event.charactersIgnoringModifiers == "f" { previewVisible = false; updatePreview(); panel.makeFirstResponder(search); return true }
        if modifiers.contains(.command), event.charactersIgnoringModifiers == "c" {
            if let hovered { restore(hovered, paste: false); return true }
            if editingSearch || (panel.firstResponder === previewText && previewText.selectedRange().length > 0) { return false }
            restore(selected, paste: false); return true
        }
        if modifiers.contains(.command), event.charactersIgnoringModifiers == "p", !editingSearch { pinClip(); return true }
        if event.keyCode == 36, modifiers.isEmpty { pasteClip(); return true }
        if [125, 126].contains(event.keyCode), modifiers.isEmpty {
            let row = max(0, min(filtered.count - 1, table.selectedRow + (event.keyCode == 125 ? 1 : -1)))
            if !filtered.isEmpty { table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false); table.scrollRowToVisible(row); panel.makeFirstResponder(previewVisible ? nil : table) }
            return true
        }
        if event.keyCode == 49, modifiers.isEmpty, !editingSearch {
            if let hovered, let index = filtered.firstIndex(where: { $0.id == hovered.id }) { table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false) }
            previewVisible.toggle(); updatePreview()
            panel.makeFirstResponder(previewVisible ? nil : table)
            return true
        }
        return false
    }
    @objc private func pasteClip() { restore(selected, paste: true) }
    private func restore(_ clip: Clip?, paste: Bool) {
        guard let clip else { return }
        if paste && !AXIsProcessTrusted() {
            report("Direct paste needs Accessibility permission. Press ⌘C to copy, or enable Palette in System Settings → Privacy & Security → Accessibility.")
            return
        }
        let target = previousApp
        if paste && (target == nil || target!.isTerminated) { report("No destination app. Press ⌘C, then paste where you need it."); return }
        do {
            try ClipboardSupport.restore(clip.dictionary, to: .general)
            changeCount = NSPasteboard.general.changeCount
            dismiss()
            if paste, let target {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                    guard NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processIdentifier,
                          let down = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true),
                          let up = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false) else {
                        self?.show(); self?.report("Could not focus the destination. The clip is copied; paste it manually."); return
                    }
                    down.flags = .maskCommand; up.flags = .maskCommand
                    down.post(tap: .cghidEventTap); up.post(tap: .cghidEventTap)
                }
            }
        } catch { report(error.localizedDescription) }
    }
    private func report(_ text: String?) {
        issue = text
        more.image = NSImage(systemSymbolName: text == nil ? "ellipsis" : "exclamationmark.circle", accessibilityDescription: "More")
        more.toolTip = text
        statusItem?.button?.toolTip = text ?? (policy.enabled ? "Palette · ⌘⇧V" : "Palette · Capture paused")
    }
    @objc private func showIssue() {
        guard let issue else { return }
        let alert = NSAlert(); alert.messageText = "Palette"; alert.informativeText = issue
        alert.beginSheetModal(for: panel) { [weak self] _ in
            guard let self, self.historyAvailable == true else { return }
            self.report(self.shortcutError)
        }
    }
    @objc private func pinClip() { if let clip = selected { store?.pin(clip.id) } }
    @objc private func pinContextClip() { if let clip = contextClip { store?.pin(clip.id) } }
    @objc private func deleteClip() { if let clip = contextClip { store?.remove(clip.id) } }
    @objc private func quit() { NSApp.terminate(nil) }
    @objc private func openMenu(_ sender: NSButton) {
        let menu = NSMenu()
        if issue != nil { menu.addItem(withTitle: "Details…", action: #selector(showIssue), keyEquivalent: "").target = self; menu.addItem(.separator()) }
        menu.addItem(withTitle: policy.enabled ? "Pause capture" : "Resume capture", action: #selector(toggleCapture), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Palette", action: #selector(quit), keyEquivalent: "q").target = self
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.maxY + 4), in: sender)
    }
    @objc private func toggleCapture() { var next = policy; next.enabled.toggle(); store?.setPolicy(next) }
    @objc private func openSettings() {
        guard store != nil, historyAvailable == true else { return }
        let settings = SettingsPanel(policy: policy, count: clips.filter { !$0.pinned }.count)
        settings.onSave = { [weak self] next in self?.store.setPolicy(next) }
        settings.onClear = { [weak self] in self?.store.clearUnpinned() }
        settingsPanel = settings
        panel.beginSheet(settings) { [weak self] _ in self?.settingsPanel = nil; self?.panel.makeFirstResponder(self?.table) }
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(openSettings) || menuItem.action == #selector(toggleCapture) { return historyAvailable == true }
        return true
    }

    private func installShortcut() {
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let callback: EventHandlerUPP = { _, _, pointer in
            guard let pointer else { return noErr }
            let owner = Unmanaged<PaletteAppDelegate>.fromOpaque(pointer).takeUnretainedValue()
            DispatchQueue.main.async { owner.toggle() }
            return noErr
        }
        let status = InstallEventHandler(GetApplicationEventTarget(), callback, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &eventHandlerRef)
        let registered = RegisterEventHotKey(UInt32(kVK_ANSI_V), UInt32(cmdKey | shiftKey), EventHotKeyID(signature: 0x50414C54, id: 1), GetApplicationEventTarget(), 0, &shortcutRef)
        if status != noErr || registered != noErr {
            shortcutError = "⌘⇧V is in use. Open Palette from its menu bar icon."
            report(shortcutError!)
        }
    }
}
