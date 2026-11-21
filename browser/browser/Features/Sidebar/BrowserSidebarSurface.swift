import SwiftUI

struct BrowserSidebarSurface: View, Animatable {
    let store: BrowserStore
    let height: CGFloat
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.layoutDirection) private var layoutDirection
    var animatableData: CGFloat

    init(store: BrowserStore, height: CGFloat) {
        self.store = store
        self.height = height
        animatableData = store.showsSidebar ? 1 : 0
    }

    var body: some View {
        let progress = min(max(animatableData, 0), 1)
        let offset = (progress - 1) * store.sidebarRegionWidth
        let left: Alignment = layoutDirection == .leftToRight ? .topLeading : .topTrailing
        BrowserSidebar(store: store)
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

struct BrowserSidebarDocking: ViewModifier {
    let store: BrowserStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.layoutDirection) private var layoutDirection
    @State private var pageDocked: Bool
    @State private var pageCovered = false
    @State private var transition: Task<Void, Never>?

    init(store: BrowserStore) {
        self.store = store
        _pageDocked = State(initialValue: store.sidebarDocked)
    }

    func body(content: Content) -> some View {
        content
            .padding(layoutDirection == .leftToRight ? .leading : .trailing, pageDocked ? store.sidebarRegionWidth : 0)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay {
                BrowserBrandTheme.sidebarBackdrop
                    .opacity(pageCovered ? 1 : 0)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .onChange(of: store.sidebarDocked) { updateDocking() }
            .onChange(of: reduceMotion) { if reduceMotion { finishImmediately() } }
            .onDisappear(perform: finishImmediately)
    }

    private func updateDocking() {
        if reduceMotion {
            finishImmediately()
            return
        }
        guard transition == nil, pageDocked != store.sidebarDocked else { return }
        transition = Task {
            guard !Task.isCancelled else { return }
            let clock = ContinuousClock()
            let revealDeadline = clock.now + .milliseconds(145)
            await withCheckedContinuation { continuation in
                withAnimation(.easeIn(duration: 0.065), completionCriteria: .removed) {
                    pageCovered = true
                } completion: {
                    continuation.resume()
                }
            }
            guard !Task.isCancelled else { return }
            while pageDocked != store.sidebarDocked {
                withAnimation(nil) { pageDocked = store.sidebarDocked }
                do {
                    try await clock.sleep(until: min(clock.now + .milliseconds(50), revealDeadline))
                } catch { return }
            }
            withAnimation(.easeOut(duration: 0.125)) { pageCovered = false }
            transition = nil
        }
    }

    private func finishImmediately() {
        transition?.cancel()
        transition = nil
        withAnimation(nil) {
            pageDocked = store.sidebarDocked
            pageCovered = false
        }
    }
}
