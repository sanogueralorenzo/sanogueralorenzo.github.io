import SwiftUI

struct BrowserRoot: View {
    let store: BrowserStore
    @State private var windowCornerRadius: CGFloat?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                LeanBrandTheme.canvas
                if store.selectedTab?.isSettings == true {
                    BrowserSettings(store: store)
                } else if !store.visiblePages.isEmpty {
                    splitContent
                }
                BrowserSidebarSurface(
                    store: store, cornerRadius: SidebarGeometry.radius(windowCornerRadius: windowCornerRadius),
                    height: geometry.size.height)
                if !store.showsSidebar {
                    Color.clear
                        .frame(width: SidebarGeometry.revealWidth)
                        .frame(maxHeight: .infinity)
                        .overlay {
                            BrowserCollapsedSidebarHoverTracker { inside in
                                guard inside, store.window?.isKeyWindow == true else { return }
                                withAnimation(LeanMotion.floatingPane.unlessReducingMotion(reduceMotion)) {
                                    store.sidebarRevealed = true
                                }
                            }
                        }
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                }
                if store.addressPresented {
                    LeanBrandTheme.canvas.opacity(0.3).onTapGesture { store.dismissAddress() }
                    AddressPalette(store: store).id(store.addressPresentationID)
                }
                if store.recentSwitcherPresented { BrowserRecentSwitcher(store: store) }
                if let notice = store.notice ?? store.owner.storageError {
                    Text(notice).font(.callout).padding(.horizontal, 16).padding(.vertical, 10)
                        .background(LeanBrandTheme.surface, in: Capsule())
                        .padding(.top, 12).frame(maxHeight: .infinity, alignment: .top)
                        .allowsHitTesting(false)
                }
            }
            .animation(LeanMotion.floatingPane.unlessReducingMotion(reduceMotion), value: store.showsSidebar)
            .background(BrowserNativeWindowControlsBridge(isVisible: store.showsSidebar))
            .overlay { BrowserSidebarDropDestination(store: store).accessibilityHidden(true) }
        }
        .onGeometryChange(for: CGFloat?.self) { proxy in
            SidebarGeometry.windowCornerRadius(from: proxy.containerCornerInsets)
        } action: { radius in
            windowCornerRadius = radius
        }
        .sheet(isPresented: Binding(get: { store.siteSettingsPresented }, set: { store.siteSettingsPresented = $0 })) {
            BrowserSiteSettings(store: store)
        }
        .sheet(isPresented: Binding(get: { store.importPresented }, set: { store.importPresented = $0 })) {
            BrowserImportView(store: store)
        }
        .sheet(isPresented: Binding(get: { store.exportPresented }, set: { store.exportPresented = $0 })) {
            BrowserExportView(store: store)
        }
        .ignoresSafeArea()
        .tint(LeanBrandTheme.textDisplay)
    }

    private var splitContent: some View {
        BrowserNativeSplit(
            store: store, pages: store.visiblePages, split: store.activeSplit,
            drop: store.sidebarReorder.splitProjection(in: store))
    }
}
