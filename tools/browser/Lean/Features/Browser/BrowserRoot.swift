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
                } else if !store.addressPresented {
                    BrowserStartPage(store: store)
                }
                if store.showsSidebar {
                    BrowserSidebar(
                        store: store, cornerRadius: SidebarGeometry.radius(windowCornerRadius: windowCornerRadius)
                    )
                    .frame(height: max(0, geometry.size.height - SidebarGeometry.inset * 2))
                    .padding(SidebarGeometry.inset)
                    .overlay {
                        BrowserSidebarHoverTracker(isRevealedByPointer: store.sidebarRevealed) { inside in
                            store.sidebarRevealed = inside
                        }
                        .padding(SidebarGeometry.inset - SidebarGeometry.hoverMargin)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .transition(.move(edge: .leading).combined(with: .opacity))
                }
                if !store.showsSidebar {
                    Color.clear
                        .frame(width: SidebarGeometry.hoverMargin)
                        .frame(maxHeight: .infinity)
                        .overlay {
                            BrowserCollapsedSidebarHoverTracker { inside in
                                guard inside, store.window?.isKeyWindow == true else { return }
                                store.sidebarRevealed = true
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
            .background(BrowserNativeWindowControlsBridge(isVisible: store.showsSidebar))
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: store.showsSidebar)
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

    @ViewBuilder
    private var splitContent: some View {
        if let split = store.activeSplit {
            BrowserNativeSplit(store: store, pages: store.visiblePages, split: split)
        } else if let page = store.visiblePages.first {
            pane(page)
        }
    }

    private func pane(_ page: BrowserPage) -> some View {
        BrowserPageContent(page: page, store: store)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay {
                if store.activeSplit != nil, store.selectedTab?.id == page.id {
                    Rectangle().stroke(LeanBrandTheme.line, lineWidth: 1).allowsHitTesting(false)
                }
            }
    }
}
