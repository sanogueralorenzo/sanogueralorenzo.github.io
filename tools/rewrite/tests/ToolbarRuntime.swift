import AppKit

@main
@MainActor
final class ToolbarRuntime: NSObject, NSApplicationDelegate {
    let toolbar = SelectionToolbar()
    let watcher = SelectionWatcher(capture: {
        let source = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.TextEdit").first
        return try? CapturedSelection.capture(sourceApp: CommandLine.arguments.contains("--foreground") ? nil : source)
    })
    var selection: CapturedSelection?
    var presentations = 0
    static func main() {
        let app = NSApplication.shared, owner = ToolbarRuntime()
        app.delegate = owner; app.setActivationPolicy(.accessory)
        withExtendedLifetime(owner) { app.run() }
    }
    func buttons(_ view: NSView) -> [NSButton] {
        (view as? NSButton).map { [$0] } ?? view.subviews.flatMap { buttons($0) }
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            do {
                let live = CommandLine.arguments.contains("--selection")
                let clipboardCount = NSPasteboard.general.changeCount
                if live {
                    print("Select the fixture now; checking in five seconds."); fflush(stdout)
                    try await Task.sleep(nanoseconds: 5_000_000_000)
                    let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
                    let source = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.TextEdit").first
                    let captured = try CapturedSelection.capture(sourceApp: CommandLine.arguments.contains("--foreground") ? nil : source)
                    guard captured.text == "She go to the library yesterday." else {
                        throw RewriteError.message("Select the disposable sentence in TextEdit before running --selection.")
                    }
                    watcher.onSelection = { [weak self] selection in
                        self?.selection = selection; self?.presentations += 1; self?.toolbar.show(at: selection.point)
                    }
                    watcher.onHide = { [weak self] in self?.toolbar.hide() }
                    watcher.interactionWindow = toolbar.panel
                    watcher.start()
                    try await Task.sleep(nanoseconds: 1_500_000_000)
                    precondition(presentations == 1 && toolbar.panel.isVisible, "automatic appearance after selection settles")
                    precondition(NSWorkspace.shared.frontmostApplication?.processIdentifier == front, "toolbar must not steal foreground focus")
                    precondition(selection?.matches(captured) == true, "source selection preserved")
                    precondition(selection?.replacementLimitation() == nil, "selection remains safely replaceable")
                } else { toolbar.show(at: NSPoint(x: 400, y: 600)) }
                precondition(!toolbar.panel.canBecomeKey && !toolbar.panel.canBecomeMain, "nonactivating toolbar")
                let view = toolbar.panel.contentView!
                view.layoutSubtreeIfNeeded()
                let controls = buttons(view)
                var actions: [EditAction] = []
                toolbar.onChoose = { actions.append($0) }
                for action in EditAction.allCases {
                    let button = controls.first { $0.title == action.rawValue }!
                    precondition(view.bounds.contains(button.convert(button.bounds, to: view)), "button must fit in toolbar")
                    button.performClick(nil)
                }
                precondition(actions == EditAction.allCases, "all six direct actions dispatch")
                let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
                view.cacheDisplay(in: view.bounds, to: bitmap)
                try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
                for screen in NSScreen.screens {
                    for point in [NSPoint(x: screen.frame.minX, y: screen.frame.minY), NSPoint(x: screen.frame.maxX - 1, y: screen.frame.maxY - 1)] {
                        toolbar.show(at: point)
                        precondition(screen.visibleFrame.contains(toolbar.panel.frame), "toolbar stays within screen edges")
                    }
                }
                toolbar.onDismiss = { [weak self] in self?.watcher.dismiss(); self?.toolbar.hide() }
                controls.first { $0.image != nil }!.performClick(nil)
                precondition(!toolbar.panel.isVisible, "close dismisses toolbar")
                if live {
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                    precondition(!toolbar.panel.isVisible && presentations == 1, "dismissed selection stays dismissed")
                }
                if live && CommandLine.arguments.contains("--changed") {
                    let original = selection!
                    print("Select just 'library' in the fixture now; checking for up to 30 seconds."); fflush(stdout)
                    for _ in 0..<120 {
                        if selection?.text == "library" && toolbar.panel.isVisible { break }
                        try await Task.sleep(nanoseconds: 250_000_000)
                    }
                    precondition(selection?.text == "library" && toolbar.panel.isVisible && presentations == 2, "new selection gets a new toolbar")
                    precondition(original.invalidated && original.replacementLimitation() != nil, "previous selection cannot replace")
                    watcher.isEnabled = { false }
                    try await Task.sleep(nanoseconds: 700_000_000)
                    precondition(!toolbar.panel.isVisible, "settings and active requests suppress the toolbar")
                    watcher.isEnabled = { true }
                    try await Task.sleep(nanoseconds: 700_000_000)
                    precondition(!toolbar.panel.isVisible, "resuming does not resurrect dismissed selection")
                    print("PASS changed selection, stale capture rejection, disabled watcher, resume suppression")
                }
                watcher.stop(); toolbar.hide()
                precondition(NSPasteboard.general.changeCount == clipboardCount, "clipboard unchanged")
                print("PASS toolbar layout, six actions, dismissal, clipboard\(live ? ", automatic selection detection, source focus, safe capture, no resurfacing" : "")")
                NSApp.terminate(nil)
            } catch { print(error.localizedDescription); exit(1) }
        }
    }
}
