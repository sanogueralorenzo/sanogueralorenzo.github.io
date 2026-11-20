import SwiftUI

struct BrowserRoot: View {
    let store: BrowserStore
    @State private var windowCornerRadius: CGFloat?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.layoutDirection) private var layoutDirection

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                BrowserBrandTheme.canvas
                pageContent.padding(
                    layoutDirection == .leftToRight ? .leading : .trailing,
                    store.sidebarDocked ? store.sidebarRegionWidth : 0
                )
                BrowserSidebarSurface(store: store, height: geometry.size.height)
                    .animation(BrowserMotion.floatingPane.unlessReducingMotion(reduceMotion), value: store.showsSidebar)
                if store.addressPresented {
                    AddressPalette(
                        store: store, cornerRadius: windowCornerRadius ?? SidebarGeometry.defaultWindowRadius
                    )
                    .id(store.addressPresentationID)
                }
                if store.recentSwitcherPresented { BrowserRecentSwitcher(store: store) }
                if let notice = store.notice ?? store.owner.storageError {
                    Text(notice).font(.callout).padding(.horizontal, 16).padding(.vertical, 10)
                        .background(BrowserBrandTheme.surface, in: Capsule())
                        .padding(.top, 12).frame(maxHeight: .infinity, alignment: .top)
                        .allowsHitTesting(false)
                }
            }
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
        .frame(minWidth: 700, minHeight: 480)
        .ignoresSafeArea()
        .tint(BrowserBrandTheme.textDisplay)
    }

    @ViewBuilder private var pageContent: some View {
        if store.selectedTab?.isSettings == true {
            BrowserSettings(store: store)
        } else if !store.visiblePages.isEmpty {
            BrowserNativeSplit(
                store: store, pages: store.visiblePages, split: store.activeSplit,
                drop: store.sidebarReorder.splitProjection(in: store))
        }
    }
}
