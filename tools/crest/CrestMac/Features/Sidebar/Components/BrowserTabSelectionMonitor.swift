import AppKit
import SwiftUI

/// Routes sidebar selection keys and modifier clicks before row activation.
struct BrowserTabSelectionMonitor: View {
    @Environment(BrowserSidebarInteractionState.self) private var sidebarInteraction
    let browser: BrowserStore
    let spaceAccess: BrowserSpaceAccessController
    let assignment: BrowserSpaceRuntimeAssignment
    let activate: (UUID) -> Void
    var ownsFocus = false

    var body: some View {
        GeometryReader { proxy in
            Bridge(
                browser: browser, sidebarInteraction: sidebarInteraction, spaceAccess: spaceAccess,
                assignment: assignment, activate: activate, ownsFocus: ownsFocus,
                globalFrame: proxy.frame(in: .global))
        }
    }

    private struct Bridge: NSViewRepresentable {
        let browser: BrowserStore
        let sidebarInteraction: BrowserSidebarInteractionState
        let spaceAccess: BrowserSpaceAccessController
        let assignment: BrowserSpaceRuntimeAssignment
        let activate: (UUID) -> Void
        let ownsFocus: Bool
        let globalFrame: CGRect

        func makeNSView(context: Context) -> SelectionView { SelectionView() }

        func updateNSView(_ view: SelectionView, context: Context) {
            view.browser = browser
            view.sidebarInteraction = sidebarInteraction
            view.spaceAccess = spaceAccess
            view.assignment = assignment
            view.activate = activate
            view.globalFrame = globalFrame
            if ownsFocus, browser.selectedSpaceID == assignment.spaceID,
                view.window?.attachedSheet == nil,
                view.window?.firstResponder !== view
            {
                view.window?.makeFirstResponder(view)
            }
        }

        static func dismantleNSView(_ view: SelectionView, coordinator: ()) { view.stop() }
    }

    final class SelectionView: NSView {
        weak var browser: BrowserStore?
        weak var sidebarInteraction: BrowserSidebarInteractionState?
        weak var spaceAccess: BrowserSpaceAccessController?
        var assignment: BrowserSpaceRuntimeAssignment?
        var activate: ((UUID) -> Void)?
        var globalFrame: CGRect = .zero
        private var monitor: Any?
        private var windowObservers: [NSObjectProtocol] = []
        private var consumedDown = false
        override var acceptsFirstResponder: Bool { true }
        override var isFlipped: Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func resignFirstResponder() -> Bool {
            browser?.tabMultiSelection.ownsKeyboardFocus = false
            return super.resignFirstResponder()
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stop()
            guard let window else { return }
            for name in [NSWindow.willCloseNotification, NSWindow.didResignKeyNotification] {
                windowObservers.append(
                    NotificationCenter.default.addObserver(
                        forName: name, object: window, queue: .main
                    ) { [weak self] _ in
                        MainActor.assumeIsolated { self?.sidebarInteraction?.cancel() }
                    })
            }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [
                .leftMouseDown, .leftMouseDragged, .leftMouseUp, .rightMouseDown, .keyDown,
            ]) {
                [weak self] event in
                guard let self else { return event }
                return self.handle(event)
            }
        }

        func stop() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            windowObservers.forEach(NotificationCenter.default.removeObserver)
            windowObservers.removeAll()
        }

        func handle(_ event: NSEvent) -> NSEvent? {
            guard let eventWindow = window, event.window === eventWindow else { return event }
            if event.type == .leftMouseDragged || event.type == .leftMouseUp {
                let local = convert(event.locationInWindow, from: nil)
                let global = CGPoint(x: globalFrame.minX + local.x, y: globalFrame.minY + local.y)
                sidebarInteraction?.sidebarReorderState.forwardPointerContinuation(
                    at: global, released: event.type == .leftMouseUp, eventTimestamp: event.timestamp)
                if event.type == .leftMouseDragged { return event }
            }
            guard let browser, let sidebarInteraction, let spaceAccess, let assignment,
                browser.selectedSpaceID == assignment.spaceID
            else { return event }
            guard
                browser.selectedUnlockedSpace(matching: assignment, accessController: spaceAccess) != nil
            else {
                browser.tabMultiSelection.clear()
                return event
            }
            let selection = browser.tabMultiSelection
            if event.type == .keyDown {
                if BrowserShortcutHardwareKeyCode(rawValue: event.keyCode) == .escape,
                    sidebarInteraction.sidebarReorderState.hasLiftInFlight
                {
                    sidebarInteraction.sidebarReorderState.cancel()
                    selection.clear()
                    return nil
                }
                guard window?.firstResponder === self else { return event }
                return handleKey(event, browser: browser)
            }
            if event.type == .leftMouseUp {
                if consumedDown {
                    consumedDown = false
                    return nil
                }
                return event
            }
            guard let window,
                let id = BrowserNativeTabSelectionTarget.TargetView.item(
                    at: event.locationInWindow, in: window, browser: browser, assignment: assignment)
            else {
                selection.clear()
                return event
            }
            let units = BrowserSidebarSelection.itemUnits(in: browser)
            selection.reconcile(units: units)
            if event.type == .rightMouseDown || event.modifierFlags.contains(.control) {
                if !selection.contains(id) { selection.clear() }
                return event
            }
            let command = event.modifierFlags.contains(.command)
            let shift = event.modifierFlags.contains(.shift)
            if command || shift {
                selection.click(
                    id, units: units, command: command, shift: shift,
                    activeItem: browser.selectedTabID(in: assignment.spaceID).map(BrowserSelectionItemID.tab))
                window.makeFirstResponder(self)
                consumedDown = true
                return nil
            }
            // Preserve a selected set on mouse-down so dragging it carries the
            // set. The activation button collapses it only after a plain click.
            if !selection.contains(id) { selection.click(id, units: units) }
            return event
        }

        private func handleKey(_ event: NSEvent, browser: BrowserStore) -> NSEvent? {
            guard let sidebarInteraction else { return event }
            let selection = browser.tabMultiSelection
            let units = BrowserSidebarSelection.itemUnits(in: browser)
            selection.reconcile(units: units)
            let command = event.modifierFlags.contains(.command)
            let shift = event.modifierFlags.contains(.shift)
            if BrowserShortcutHardwareKeyCode(rawValue: event.keyCode) == .escape {
                sidebarInteraction.sidebarReorderState.cancel()
                selection.clear()
                return nil
            }
            if command, event.charactersIgnoringModifiers?.lowercased() == "a" {
                if shift { selection.clear() } else { selection.selectAll(units: units) }
                return nil
            }
            if command, !shift, !event.modifierFlags.contains(.option),
                !event.modifierFlags.contains(.control), let id = selection.focusedItem,
                let request = BrowserSidebarSelection.capture(for: id, in: browser), let spaceAccess
            {
                let actions = BrowserTabBatchActions(browser: browser, spaceAccess: spaceAccess)
                switch event.charactersIgnoringModifiers?.lowercased() {
                case "c":
                    actions.copyLinks(request)
                    return nil
                case "d":
                    actions.perform(browser.duplicating(request), for: request)
                    return nil
                case "w":
                    actions.perform(browser.closing(request), for: request)
                    return nil
                default: break
                }
                if BrowserShortcutHardwareKeyCode(rawValue: event.keyCode) == .delete {
                    actions.perform(browser.deleting(request), for: request)
                    return nil
                }
            }
            if let key = BrowserShortcutHardwareKeyCode(rawValue: event.keyCode),
                [.leftArrow, .rightArrow, .downArrow, .upArrow, .home, .end].contains(key), !units.isEmpty
            {
                let current =
                    units.firstIndex { $0.contains(selection.focusedItem ?? selection.anchorItem ?? units[0][0]) } ?? 0
                let backwards = key == .leftArrow || key == .upArrow || key == .home
                let edge = command || key == .home || key == .end
                let index =
                    edge
                    ? (backwards ? 0 : units.count - 1) : min(max(current + (backwards ? -1 : 1), 0), units.count - 1)
                selection.click(
                    units[index][0], units: units, command: command && !edge, shift: shift,
                    activeItem: assignment.flatMap { browser.selectedTabID(in: $0.spaceID) }.map(
                        BrowserSelectionItemID.tab))
                if !shift { selection.selectForKeyboard(units[index][0], units: units) }
                return nil
            }
            if BrowserShortcutHardwareKeyCode(rawValue: event.keyCode) == .returnKey, let id = selection.focusedItem {
                if let tabID = id.tabID { activate?(tabID) }
                if let folderID = id.folderID,
                    let folder = browser.shownSpace?.folders.model(folderID)
                {
                    browser.setFolderCollapsed(
                        folderID, in: browser.selectedSpaceID, isCollapsed: !folder.isCollapsed)
                }
                return nil
            }
            return event
        }

        override func selectAll(_ sender: Any?) {
            guard let browser, sidebarInteraction != nil else { return }
            browser.tabMultiSelection.selectAll(
                units: BrowserSidebarSelection.itemUnits(in: browser))
        }
    }
}
