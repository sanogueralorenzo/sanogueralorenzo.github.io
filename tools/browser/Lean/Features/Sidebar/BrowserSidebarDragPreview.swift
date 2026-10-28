import AppKit
import Observation
import SwiftUI

/// Crest draws lifts in an inert child window so WKWebView cannot cover or
/// clip them. One host owns the preview through lift, shape changes and landing.
@MainActor
final class BrowserSidebarDragPreview {
    @Observable final class Presentation {
        let tabs: [BrowserTab]
        let title: String
        let count: Int
        let symbol: String
        let spaceColor: Int?
        let spaceHeight: CGFloat
        var pinned: Bool
        var width: CGFloat
        var landing = false
        var opacity = 1.0
        var pointer = CGPoint.zero
        init(
            tabs: [BrowserTab], title: String, count: Int, symbol: String, spaceColor: Int?, spaceHeight: CGFloat,
            pinned: Bool, width: CGFloat
        ) {
            self.tabs = tabs
            self.title = title
            self.count = count
            self.symbol = symbol
            self.spaceColor = spaceColor
            self.spaceHeight = spaceHeight
            self.pinned = pinned
            self.width = width
        }
        var height: CGFloat {
            if spaceColor != nil { return spaceHeight }
            return pinned ? SidebarGeometry.rowHeight : CGFloat(max(1, tabs.count)) * SidebarGeometry.rowHeight
        }
    }

    private let presentation: Presentation
    private let panel: NSPanel
    private let anchor: CGPoint
    private let reduceMotion: Bool
    private let sourceFrame: CGRect
    private let sourcePinned: Bool
    private let sourceWidth: CGFloat
    private let parentFrame: CGRect
    private var closeObserver: NSObjectProtocol?
    private var completion: Task<Void, Never>?

    init(store: BrowserStore, payload: BrowserDragPayload, title: String, frame: CGRect, grab: CGPoint) {
        let space = store.session.spaces.first { $0.id == payload.spaceID }
        let tabs = payload.ids.compactMap { id in space?.tabs.first { $0.id == id } }
        let pinned = tabs.count == 1 && payload.folderIDs.isEmpty && tabs.first?.placement == .pinned
        sourcePinned = pinned
        sourceWidth = pinned || payload.kind == .space ? frame.width : store.sidebarWidth - 32
        presentation = Presentation(
            tabs: Array(tabs.prefix(4)), title: title, count: payload.ids.count + payload.folderIDs.count,
            symbol: payload.kind == .space ? "circle.fill" : "folder.fill",
            spaceColor: payload.kind == .space ? space?.color : nil, spaceHeight: frame.height,
            pinned: pinned, width: sourceWidth)
        anchor = CGPoint(
            x: min(1, max(0, grab.x / max(1, frame.width))), y: min(1, max(0, grab.y / max(1, frame.height))))
        reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        sourceFrame = frame
        parentFrame = store.window?.frame ?? frame
        panel = NSPanel(
            contentRect: parentFrame,
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.transient, .ignoresCycle, .fullScreenAuxiliary]
        panel.animationBehavior = .none
        panel.level = .floating
        panel.contentView = NSHostingView(
            rootView: Preview(presentation: presentation, anchor: anchor, reduceMotion: reduceMotion))
        move(to: NSEvent.mouseLocation, target: nil, frame: nil)
        if let window = store.window {
            panel.appearance = window.effectiveAppearance
            window.addChildWindow(panel, ordered: .above)
            closeObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification, object: window, queue: .main
            ) { [weak self] _ in MainActor.assumeIsolated { self?.close() } }
        }
    }

    func move(to point: NSPoint, target: BrowserSidebarReorderState.Target?, frame: CGRect?) {
        let pinned = target.map { $0.placement == .pinned } ?? sourcePinned
        let canPin = presentation.tabs.count == 1 && presentation.count == 1
        presentation.pinned = pinned && canPin
        if let frame {
            presentation.width = frame.width
        } else {
            presentation.width = sourceWidth
        }
        let body = CGRect(
            x: point.x - presentation.width * anchor.x,
            y: point.y - presentation.height * (1 - anchor.y),
            width: presentation.width, height: presentation.height)
        panel.setFrame((panel.parent?.frame ?? parentFrame).union(body.insetBy(dx: -16, dy: -16)), display: true)
        presentation.pointer = CGPoint(x: point.x - panel.frame.minX, y: panel.frame.maxY - point.y)
    }

    func finish(accepted: Bool, landing: CGRect?, completion: @escaping @MainActor () -> Void) {
        presentation.landing = true
        if let destination = accepted ? landing : sourceFrame {
            if !accepted { presentation.pinned = sourcePinned }
            presentation.width = destination.width
            // Keep a stable canvas through the spring so WebKit, clipping and
            // native window animation cannot change the landing curve.
            let previous = panel.frame
            panel.setFrame(previous.union(destination.insetBy(dx: -16, dy: -16)), display: true)
            presentation.pointer.x += previous.minX - panel.frame.minX
            presentation.pointer.y += panel.frame.maxY - previous.maxY
            withAnimation(LeanMotion.dragSource.unlessReducingMotion(reduceMotion)) {
                presentation.pointer = CGPoint(
                    x: destination.minX + presentation.width * anchor.x - panel.frame.minX,
                    y: panel.frame.maxY - destination.maxY + presentation.height * anchor.y)
            }
        } else {
            presentation.opacity = 0
        }
        self.completion = Task { [self] in
            if !reduceMotion { try? await Task.sleep(for: .milliseconds(200)) }
            close()
            completion()
        }
    }

    func cancel() {
        completion?.cancel()
        close()
    }

    private func close() {
        if let closeObserver { NotificationCenter.default.removeObserver(closeObserver) }
        closeObserver = nil
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
        panel.contentView = nil
    }

    private struct Preview: View {
        let presentation: Presentation
        let anchor: CGPoint
        let reduceMotion: Bool
        var body: some View {
            VStack(spacing: 0) {
                if let color = presentation.spaceColor {
                    Circle().fill(Color.space(color)).frame(width: 12, height: 12)
                        .frame(width: presentation.width, height: presentation.height)
                } else if presentation.tabs.isEmpty {
                    row(nil, title: presentation.title)
                } else {
                    ForEach(presentation.tabs) { tab in row(tab, title: tab.customTitle ?? tab.title) }
                }
            }
            .frame(width: presentation.width, height: presentation.height, alignment: .top)
            .background(LeanBrandTheme.surface, in: RoundedRectangle(cornerRadius: 20))
            .overlay(alignment: .topTrailing) {
                if presentation.count > 1 {
                    Text("\(presentation.count)").font(.caption.weight(.semibold)).padding(5)
                        .background(LeanBrandTheme.surface, in: Circle()).offset(x: 5, y: -5)
                }
            }
            .shadow(color: .black.opacity(0.24), radius: 10, y: 5)
            .scaleEffect(presentation.landing ? 1 : presentation.spaceColor == nil ? 1.04 : 1.08, anchor: .topLeading)
            .opacity(presentation.opacity)
            .animation(LeanMotion.dragPreview.unlessReducingMotion(reduceMotion), value: presentation.pinned)
            .animation(LeanMotion.dragPreview.unlessReducingMotion(reduceMotion), value: presentation.width)
            .animation(LeanMotion.dragSource.unlessReducingMotion(reduceMotion), value: presentation.landing)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.10), value: presentation.opacity)
            .offset(x: presentation.width * (0.5 - anchor.x), y: presentation.height * (0.5 - anchor.y))
            .position(presentation.pointer)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        private func row(_ tab: BrowserTab?, title: String) -> some View {
            HStack(spacing: 9) {
                if let tab {
                    TabIcon(tab: tab).frame(width: 28, height: 20)
                } else {
                    Image(systemName: presentation.symbol).frame(width: 28, height: 20)
                }
                if !presentation.pinned {
                    Text(title).lineLimit(1)
                    Spacer(minLength: 0)
                }
            }
            .font(.system(size: 13)).padding(.horizontal, 9)
            .frame(
                maxWidth: .infinity, minHeight: SidebarGeometry.rowHeight,
                alignment: presentation.pinned ? .center : .leading)
        }
    }
}
