import AppKit
import Observation
import SwiftUI

/// Crest draws lifts in an inert child window so WKWebView cannot cover or
/// clip them. One host owns the preview through lift, shape changes and landing.
@MainActor
final class BrowserSidebarDragPreview {
    struct Row: Identifiable {
        enum Content {
            case tab(BrowserTab)
            case folder(BrowserFolder)
            case split([BrowserTab])
        }
        let id: UUID
        let frame: CGRect
        let content: Content
    }
    @Observable final class Presentation {
        let rows: [Row]
        let sourceHeight: CGFloat
        let tab: BrowserTab?
        let title: String
        let count: Int
        let symbol: String
        let spaceColor: Int?
        let spaceHeight: CGFloat
        let snapshot: NSImage?
        var cardHeight: CGFloat?
        var pinned: Bool
        var width: CGFloat
        var landing = false
        var opacity = 1.0
        var pointer = CGPoint.zero
        init(
            rows: [Row], sourceHeight: CGFloat, tab: BrowserTab?, title: String, count: Int, symbol: String,
            spaceColor: Int?, spaceHeight: CGFloat,
            snapshot: NSImage?, pinned: Bool, width: CGFloat
        ) {
            self.rows = rows
            self.sourceHeight = sourceHeight
            self.tab = tab
            self.title = title
            self.count = count
            self.symbol = symbol
            self.spaceColor = spaceColor
            self.spaceHeight = spaceHeight
            self.snapshot = snapshot
            self.pinned = pinned
            self.width = width
        }
        var height: CGFloat {
            if spaceColor != nil { return spaceHeight }
            if let cardHeight { return cardHeight }
            return pinned ? SidebarGeometry.rowHeight : sourceHeight
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
        let rows = store.sidebarReorder.previewRows(in: store)
        let tab: BrowserTab?
        if rows.count == 1, case .tab(let value) = rows[0].content { tab = value } else { tab = nil }
        let pinned = tab?.placement == .pinned
        sourcePinned = pinned
        sourceWidth = pinned || payload.kind == .space ? frame.width : store.sidebarWidth - 32
        presentation = Presentation(
            rows: rows, sourceHeight: frame.height, tab: tab, title: title,
            count: store.owner.sidebarLift?.rootIDs.count ?? 1,
            symbol: payload.kind == .space ? "circle.fill" : "folder.fill",
            spaceColor: payload.kind == .space ? space?.color : nil, spaceHeight: frame.height,
            snapshot: tab.flatMap { store.owner.pages[$0.id]?.mirrorImage },
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
        let pinned: Bool
        if case .space = target?.kind { pinned = sourcePinned } else { pinned = target.map(\.isPinned) ?? sourcePinned }
        let canPin = presentation.tab != nil && presentation.count == 1
        presentation.pinned = pinned && canPin
        let isSplit: Bool
        if let target, case .split = target.kind { isSplit = true } else { isSplit = false }
        let card = isSplit && presentation.tab != nil && presentation.count == 1
        presentation.cardHeight = card ? frame?.height : nil
        if let frame, !isSplit || card {
            presentation.width = frame.width
        } else {
            presentation.width = sourceWidth
        }
        let body = CGRect(
            x: point.x - presentation.width * anchor.x,
            y: point.y - presentation.height * (1 - anchor.y),
            width: presentation.width, height: presentation.height)
        let scale: CGFloat = presentation.spaceColor == nil ? 1.04 : 1.08
        let drawing = CGRect(
            x: body.minX, y: body.maxY - body.height * scale,
            width: body.width * scale, height: body.height * scale
        ).insetBy(dx: -16, dy: -16)
        panel.setFrame((panel.parent?.frame ?? parentFrame).union(drawing), display: true)
        presentation.pointer = CGPoint(x: point.x - panel.frame.minX, y: panel.frame.maxY - point.y)
    }

    func finish(accepted: Bool, landing: CGRect?, completion: @escaping @MainActor () -> Void) {
        presentation.landing = true
        if let destination = accepted ? landing : sourceFrame {
            if !accepted {
                presentation.pinned = sourcePinned
                presentation.cardHeight = nil
            }
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
            ZStack(alignment: .topLeading) {
                if let color = presentation.spaceColor {
                    Circle().fill(Color.space(color)).frame(width: 12, height: 12)
                        .frame(width: presentation.width, height: presentation.height)
                } else if presentation.rows.isEmpty {
                    row(nil, title: presentation.title)
                } else if let tab = presentation.tab {
                    row(tab, title: tab.customTitle ?? tab.title)
                } else {
                    ForEach(presentation.rows) { item in
                        previewRow(item)
                            .frame(
                                width: min(item.frame.width, max(0, presentation.width - item.frame.minX)),
                                height: item.frame.height, alignment: .topLeading
                            )
                            .offset(x: item.frame.minX, y: item.frame.minY)
                    }
                }
            }
            .frame(width: presentation.width, height: presentation.height, alignment: .top)
            .background(alignment: .bottom) {
                if let height = presentation.cardHeight, let snapshot = presentation.snapshot {
                    Image(nsImage: snapshot).resizable().scaledToFill()
                        .frame(width: presentation.width, height: max(0, height - SidebarGeometry.rowHeight)).clipped()
                }
            }
            .background(
                LeanBrandTheme.surface, in: RoundedRectangle(cornerRadius: presentation.cardHeight == nil ? 20 : 13)
            )
            .clipShape(RoundedRectangle(cornerRadius: presentation.cardHeight == nil ? 20 : 13))
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
            .animation(LeanMotion.dragPreview.unlessReducingMotion(reduceMotion), value: presentation.cardHeight)
            .animation(LeanMotion.dragSource.unlessReducingMotion(reduceMotion), value: presentation.landing)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.10), value: presentation.opacity)
            .offset(x: presentation.width * (0.5 - anchor.x), y: presentation.height * (0.5 - anchor.y))
            .position(presentation.pointer)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        @ViewBuilder private func previewRow(_ item: Row) -> some View {
            switch item.content {
            case .tab(let tab): row(tab, title: tab.customTitle ?? tab.title)
            case .folder(let folder):
                HStack(spacing: 9) {
                    Image(systemName: folder.isExpanded ? "folder.fill" : "folder").frame(width: 28)
                    Text(folder.title).lineLimit(1)
                    Spacer(minLength: 0)
                }.font(.system(size: 13)).padding(.horizontal, 10).frame(height: SidebarGeometry.rowHeight)
            case .split(let tabs):
                VStack(spacing: 0) {
                    Label("\(tabs.count)", systemImage: "rectangle.split.2x1")
                        .font(.caption.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
                        .padding(.horizontal, 9)
                    ForEach(tabs) { tab in row(tab, title: tab.customTitle ?? tab.title).padding(.vertical, 1) }
                }.padding(4).background(.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 16))
            }
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
