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
    @State private var transitionID: UUID?
    @State private var revealAt: TimeInterval?
    private let fadeDuration: TimeInterval = 0.025
    private let holdDuration: TimeInterval = 0.35

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
        if transitionID != nil {
            guard let revealAt else { return }
            if ProcessInfo.processInfo.systemUptime < revealAt {
                resizePage()
                return
            }
        }
        let id = UUID()
        transitionID = id
        revealAt = nil
        withAnimation(.linear(duration: fadeDuration), completionCriteria: .removed) {
            pageCovered = true
        } completion: {
            resizeAndReveal(id: id)
        }
    }

    private func resizeAndReveal(id: UUID) {
        guard transitionID == id else { return }
        let fadeOut = Animation.linear(duration: fadeDuration)
        guard pageDocked != store.sidebarDocked else {
            transitionID = nil
            withAnimation(fadeOut) { pageCovered = false }
            return
        }
        resizePage()
        revealAt = ProcessInfo.processInfo.systemUptime + holdDuration
        withAnimation(fadeOut.delay(holdDuration), completionCriteria: .removed) {
            pageCovered = false
        } completion: {
            guard transitionID == id else { return }
            transitionID = nil
            revealAt = nil
        }
    }

    private func resizePage() {
        withAnimation(nil) { pageDocked = store.sidebarDocked }
    }

    private func finishImmediately() {
        transitionID = nil
        revealAt = nil
        withAnimation(nil) {
            pageDocked = store.sidebarDocked
            pageCovered = false
        }
    }
}
