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
                .accessibilityHidden(store.addressPresented)
                BrowserSidebarSurface(store: store, height: geometry.size.height)
                    .animation(BrowserMotion.floatingPane.unlessReducingMotion(reduceMotion), value: store.showsSidebar)
                    .accessibilityHidden(store.addressPresented)
                if store.addressPresented {
                    AddressPalette(
                        store: store, cornerRadius: windowCornerRadius ?? SidebarGeometry.defaultWindowRadius
                    )
                    .id(store.addressPresentationID)
                }
                if store.recentSwitcherPresented { BrowserRecentSwitcher(store: store) }
                if let notice = store.notice ?? store.owner.storageError {
                    banner(Text(notice)).allowsHitTesting(false)
                } else if store.owner.showsRecoveryNotice, !store.addressPresented {
                    banner(
                        HStack(spacing: 12) {
                            Text("Recovered the previous saved session. The damaged file has been preserved.")
                            Button("Dismiss") { store.owner.showsRecoveryNotice = false }
                                .buttonStyle(.borderless)
                        })
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
        .frame(minWidth: 700, minHeight: 480)
        .ignoresSafeArea()
        .tint(BrowserBrandTheme.textDisplay)
    }

    private func banner(_ content: some View) -> some View {
        content.font(.callout).padding(.horizontal, 16).padding(.vertical, 10)
            .background(BrowserBrandTheme.surface, in: Capsule())
            .padding(.top, 12).frame(maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder private var pageContent: some View {
        if store.selectedTab?.isSettings == true {
            BrowserSettings(store: store)
        } else {
            let pages = store.visiblePages
            if !pages.isEmpty {
                BrowserNativeSplit(
                    store: store, pages: pages, split: store.activeSplit,
                    drop: store.sidebarReorder.splitProjection(in: store))
            }
        }
    }
}
