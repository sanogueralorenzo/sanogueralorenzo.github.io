import SwiftUI

struct BrowserSidebarSurface: View, Animatable {
    let store: BrowserStore
    let height: CGFloat
    let toggleDocking: () -> Void
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.layoutDirection) private var layoutDirection
    var animatableData: CGFloat

    init(store: BrowserStore, height: CGFloat, toggleDocking: @escaping () -> Void) {
        self.store = store
        self.height = height
        self.toggleDocking = toggleDocking
        animatableData = store.showsSidebar ? 1 : 0
    }

    var body: some View {
        let progress = min(max(animatableData, 0), 1)
        let offset = (progress - 1) * store.sidebarRegionWidth
        let left: Alignment = layoutDirection == .leftToRight ? .topLeading : .topTrailing
        BrowserSidebar(store: store, toggleDocking: toggleDocking)
            .frame(height: max(0, height - SidebarGeometry.inset * 2))
            .compositingGroup()
            .shadow(
                color: .black.opacity(reduceTransparency ? 0 : 0.24 * progress),
                radius: 12, x: 2, y: 4
            )
            .padding(SidebarGeometry.inset)
            .offset(x: offset)
            .allowsHitTesting(store.showsSidebar)
            .accessibilityHidden(!store.showsSidebar)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: left)
            .overlay(alignment: left) {
                if store.showsSidebar {
                    BrowserSidebarHoverTracker(waitsForPointer: store.utility != nil && !store.sidebarDocked) {
                        inside in
                        guard store.showsSidebar, store.sidebarRevealed != inside else { return }
                        store.sidebarRevealed = inside
                    }
                    .frame(width: store.sidebarWidth + SidebarGeometry.inset, height: height)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                } else {
                    BrowserCollapsedSidebarHoverTracker { inside in
                        guard inside, !store.showsSidebar, store.window?.isKeyWindow == true else { return }
                        store.sidebarRevealed = true
                    }
                    .frame(width: SidebarGeometry.revealWidth, height: height)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
            }
            .background(BrowserNativeWindowControlsBridge(sidebarOffset: offset))
    }
}

struct BrowserSidebarDocking<Content: View>: View {
    let store: BrowserStore
    let height: CGFloat
    @ViewBuilder let content: () -> Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.layoutDirection) private var layoutDirection
    @State private var pageDocked = false
    @State private var pageCovered = false
    @State private var revealDeadline: TimeInterval?
    @State private var coverReady = false

    var body: some View {
        ZStack {
            content()
                .padding(
                    layoutDirection == .leftToRight ? .leading : .trailing, pageDocked ? store.sidebarRegionWidth : 0
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay {
                    BrowserBrandTheme.sidebarBackdrop
                        .opacity(pageCovered ? 1 : 0)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            BrowserSidebarSurface(store: store, height: height, toggleDocking: toggleDocking)
                .animation(BrowserMotion.floatingPane.unlessReducingMotion(reduceMotion), value: store.showsSidebar)
        }
        .onChange(of: reduceMotion) { if reduceMotion { finishImmediately() } }
        .onDisappear(perform: finishImmediately)
    }

    private func toggleDocking() {
        store.sidebarDocked.toggle()
        if reduceMotion {
            finishImmediately()
            return
        }
        let now = ProcessInfo.processInfo.systemUptime
        if let revealDeadline, !coverReady || now < revealDeadline {
            if coverReady { resizePage() }
            return
        }
        let deadline = now + 0.24
        revealDeadline = deadline
        coverReady = false
        withAnimation(.linear(duration: 0.05), completionCriteria: .removed) {
            pageCovered = true
        } completion: {
            resizeAndReveal(at: deadline)
        }
    }

    private func resizeAndReveal(at deadline: TimeInterval) {
        guard revealDeadline == deadline else { return }
        let fadeOut = Animation.linear(duration: 0.04)
        guard pageDocked != store.sidebarDocked else {
            revealDeadline = nil
            withAnimation(fadeOut) { pageCovered = false }
            return
        }
        coverReady = true
        resizePage()
        let delay = max(0, deadline - ProcessInfo.processInfo.systemUptime)
        withAnimation(fadeOut.delay(delay), completionCriteria: .removed) {
            pageCovered = false
        } completion: {
            guard revealDeadline == deadline else { return }
            revealDeadline = nil
            coverReady = false
        }
    }

    private func resizePage() {
        withAnimation(nil) { pageDocked = store.sidebarDocked }
    }

    private func finishImmediately() {
        revealDeadline = nil
        coverReady = false
        withAnimation(nil) {
            pageDocked = store.sidebarDocked
            pageCovered = false
        }
    }
}
