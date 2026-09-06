import AppKit
import Carbon.HIToolbox
import ApplicationServices

final class ClipboardContent: NSView {
    var didAttach: (() -> Void)?
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { didAttach?() }
    }
}

final class ClipboardSearch: NSSearchField {
    var didFocus: (() -> Void)?
    override func mouseDown(with event: NSEvent) {
        didFocus?()
        super.mouseDown(with: event)
    }
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
        let tracking = NSTrackingArea(rect: .zero, options: [.inVisibleRect, .activeAlways, .mouseMoved, .mouseEnteredAndExited], owner: self)
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
final class PaletteAppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    private let clipboardMenu = NSMenu()
    private let content = ClipboardContent(frame: NSRect(x: 0, y: 0, width: 280, height: 260))
    private var menuOpen = false
    private let search = ClipboardSearch()
    private var searchExpanded = false
    private let table = ClipboardTable()
    private let historyScroll = NSScrollView()
    private let previewImage = NSImageView()
    private var statusItem: NSStatusItem!
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
    private let pause = NSButton()
    private let clear = NSButton()
    private var issue: String?
    private var shortcutError: String?
    private var historyAvailable: Bool?
    private let captureOnColor = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 168/255, green: 213/255, blue: 181/255, alpha: 1)
            : NSColor(srgbRed: 47/255, green: 112/255, blue: 70/255, alpha: 1)
    }
    private let captureOffColor = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 231/255, green: 165/255, blue: 165/255, alpha: 1)
            : NSColor(srgbRed: 164/255, green: 63/255, blue: 63/255, alpha: 1)
    }
    private let accent = NSColor(calibratedRed: 0.75, green: 0.69, blue: 0.9, alpha: 1)

    static func main() {
        let app = NSApplication.shared
        let delegate = PaletteAppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureContent()
        configureMenu()
        installShortcut()
        let standard = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Palette")
        let args = CommandLine.arguments
        let review = args.contains("--review")
        var directory = standard
        if review {
            guard let index = args.firstIndex(of: "--data-dir"), args.indices.contains(index + 1), args[index + 1].hasPrefix("/") else {
                report("Review mode requires --data-dir /absolute/path to a separate profile."); return
            }
            directory = URL(fileURLWithPath: args[index + 1])
            guard directory.resolvingSymlinksInPath().standardizedFileURL != standard.resolvingSymlinksInPath().standardizedFileURL else {
                report("Review mode requires a separate profile."); return
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
        RunLoop.main.add(timer!, forMode: .common)
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didDeactivateApplicationNotification, object: nil, queue: .main) { [weak self] notification in
            MainActor.assumeIsolated { self?.capture(source: notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication) }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) {
        if historyAvailable == true {
            capture()
            store?.finishWrites()
        }
        timer?.invalidate()
        if let shortcutRef { UnregisterEventHotKey(shortcutRef) }
        if let eventHandlerRef { RemoveEventHandler(eventHandlerRef) }
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        if let activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(activationObserver) }
    }

    private func configureContent() {
        let root = content
        content.didAttach = { [weak self] in
            guard let self else { return }
            self.content.window?.makeFirstResponder(self.filtered.isEmpty ? nil : self.table)
        }
        let stack = NSStackView()
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 10), stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -10), stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 10), stack.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -10)])
        let mark = NSImageView(image: NSImage(systemSymbolName: "square.on.square", accessibilityDescription: "Palette")!)
        mark.contentTintColor = accent
        mark.widthAnchor.constraint(equalToConstant: 18).isActive = true
        pause.title = "Palette"
        pause.font = .systemFont(ofSize: 13, weight: .semibold)
        pause.contentTintColor = captureOffColor
        pause.target = self; pause.action = #selector(toggleCapture)
        pause.isBordered = false; pause.isEnabled = false
        clear.image = NSImage(systemSymbolName: "trash", accessibilityDescription: "Clear history")
        clear.target = self; clear.action = #selector(clearHistory)
        clear.isBordered = false; clear.isEnabled = false
        clear.toolTip = "Clear all clipboard history"
        clear.setAccessibilityLabel("Clear all clipboard history")
        let heading = NSStackView(views: [mark, pause, NSView(), clear]); heading.spacing = 8
        heading.heightAnchor.constraint(equalToConstant: 22).isActive = true
        add(heading, to: stack)
        search.placeholderString = "Search clips or apps"
        search.delegate = self
        search.didFocus = { [weak self] in
            self?.searchExpanded = true
            self?.updateContentSize()
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
        table.target = self; table.doubleAction = #selector(pasteClip)
        table.setAccessibilityLabel("Clipboard history")
        let scroll = historyScroll; scroll.documentView = table; scroll.hasVerticalScroller = true; scroll.drawsBackground = false
        add(scroll, to: stack)
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
        clipboardMenu.delegate = self
        clipboardMenu.autoenablesItems = false
        let clipboard = NSMenuItem()
        clipboard.view = content
        clipboardMenu.addItem(clipboard)
        clipboardMenu.addItem(.separator())
        clipboardMenu.addItem(withTitle: "Quit Palette", action: #selector(quit), keyEquivalent: "q").target = self
        statusItem.menu = clipboardMenu
        let menu = NSMenu()
        let appItem = NSMenuItem(); let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Palette", action: #selector(quit), keyEquivalent: "q").target = self
        appItem.submenu = appMenu; menu.addItem(appItem)
        let edit = NSMenuItem(); let editMenu = NSMenu(title: "Edit")
        for (name, action, key) in [("Undo", "undo:", "z"), ("Cut", "cut:", "x"), ("Copy", "copy:", "c"), ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")] { editMenu.addItem(NSMenuItem(title: name, action: Selector(action), keyEquivalent: key)) }
        edit.submenu = editMenu; menu.addItem(edit); NSApp.mainMenu = menu
    }

    @objc private func toggle() { menuOpen ? dismiss() : show() }
    private func show() {
        guard !menuOpen else { return }
        statusItem.button?.performClick(nil)
    }
    func menuWillOpen(_ menu: NSMenu) {
        menuOpen = true
        store?.prune()
        if let front = NSWorkspace.shared.frontmostApplication, front.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            capture(source: front)
            previousApp = front
        }
        searchExpanded = false
        search.stringValue = ""; previewVisible = false; table.clearHover(); table.deselectAll(nil); reload()
    }
    func menuDidClose(_ menu: NSMenu) {
        menuOpen = false
        previousApp = nil
    }
    private func dismiss() { clipboardMenu.cancelTracking() }

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

    func controlTextDidChange(_ obj: Notification) { searchExpanded = true; previewVisible = false; reload() }
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
        let title = NSTextField(labelWithString: summary)
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        title.lineBreakMode = .byTruncatingTail; title.font = .systemFont(ofSize: 13, weight: .medium)
        title.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let cell = NSStackView(views: [image, title]); cell.spacing = 8; cell.edgeInsets = NSEdgeInsets(top: 4, left: 6, bottom: 4, right: 6)
        title.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6).isActive = true
        cell.toolTip = "\(clip.appName) · ⌘C Copy" + (clip.kind == .image ? " · Space Preview" : "")
        cell.setAccessibilityElement(true); cell.setAccessibilityLabel("\(summary), \(clip.appName), \(clip.kind.rawValue)")
        return cell
    }
    private func updatePreview() {
        defer { updateContentSize() }
        previewImage.isHidden = true; historyScroll.isHidden = false
        guard previewVisible, let clip = selected, clip.kind == .image,
              let thumb = clip.thumbnail?.split(separator: ",", maxSplits: 1).last,
              let data = Data(base64Encoded: String(thumb)), let image = NSImage(data: data) else {
            previewVisible = false
            return
        }
        historyScroll.isHidden = true
        previewImage.image = image; previewImage.setAccessibilityLabel(clip.summary); previewImage.isHidden = false
    }

    private func updateContentSize() {
        historyScroll.isHidden = previewVisible || (filtered.isEmpty && !searchExpanded)
        let rowsHeight = CGFloat(filtered.count) * (table.rowHeight + table.intercellSpacing.height)
        let naturalHeight = 20 + 22 + 8 + 26 + (filtered.isEmpty ? 0 : 8 + rowsHeight)
        let height = searchExpanded || previewVisible ? 260 : min(260, naturalHeight)
        guard content.frame.height != height else { return }
        table.clearHover()
        content.setFrameSize(NSSize(width: content.frame.width, height: height))
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        guard menuOpen, let window = content.window else { return false }
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        let editingSearch = window.firstResponder === search.currentEditor()
        if event.keyCode == 53 { dismiss(); return true }
        if modifiers.contains(.command), event.charactersIgnoringModifiers == "f" { searchExpanded = true; previewVisible = false; updatePreview(); window.makeFirstResponder(search); return true }
        if modifiers.contains(.command), event.charactersIgnoringModifiers == "c" {
            if let hovered { restore(hovered, paste: false); return true }
            if editingSearch { return false }
            restore(selected, paste: false); return true
        }
        if event.keyCode == 36, modifiers.isEmpty { pasteClip(); return true }
        if [125, 126].contains(event.keyCode), modifiers.isEmpty {
            let row = max(0, min(filtered.count - 1, table.selectedRow + (event.keyCode == 125 ? 1 : -1)))
            if !filtered.isEmpty { table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false); table.scrollRowToVisible(row); window.makeFirstResponder(previewVisible ? nil : table) }
            return true
        }
        if event.keyCode == 49, modifiers.isEmpty, !editingSearch {
            if let hovered, let index = filtered.firstIndex(where: { $0.id == hovered.id }) { table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false) }
            guard previewVisible || selected?.kind == .image else { return true }
            previewVisible.toggle(); updatePreview()
            window.makeFirstResponder(previewVisible ? nil : table)
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
                        self?.report("Could not focus the destination. The clip is copied; paste it manually.")
                        RunLoop.main.perform { MainActor.assumeIsolated { self?.show() } }
                        return
                    }
                    down.flags = .maskCommand; up.flags = .maskCommand
                    down.post(tap: .cghidEventTap); up.post(tap: .cghidEventTap)
                }
            }
        } catch { report(error.localizedDescription) }
    }
    private func report(_ text: String?) {
        issue = text
        let action = policy.enabled ? "Pause capture" : "Resume capture"
        pause.setAccessibilityLabel("Palette · \(action)")
        pause.toolTip = text.map { "\(action)\n\($0)" } ?? action
        pause.contentTintColor = historyAvailable == true && policy.enabled ? captureOnColor : captureOffColor
        pause.isEnabled = historyAvailable == true
        clear.isEnabled = historyAvailable == true && !clips.isEmpty
        statusItem?.button?.toolTip = text ?? (policy.enabled ? "Palette · ⌘⇧V" : "Palette · Capture paused")
    }
    @objc private func toggleCapture() {
        report(shortcutError)
        store?.toggleCapture()
    }
    @objc private func clearHistory() {
        guard historyAvailable == true, !clips.isEmpty else { return }
        report(shortcutError)
        store.clear()
        content.window?.makeFirstResponder(table)
    }
    @objc private func quit() { NSApp.terminate(nil) }

    private func installShortcut() {
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let callback: EventHandlerUPP = { _, _, pointer in
            guard let pointer else { return noErr }
            let owner = Unmanaged<PaletteAppDelegate>.fromOpaque(pointer).takeUnretainedValue()
            MainActor.assumeIsolated { owner.toggle() }
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
