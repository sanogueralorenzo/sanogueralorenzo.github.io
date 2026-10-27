import SwiftUI

struct BrowserRoot: View {
    let store: BrowserStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                CrestBrandTheme.canvas
                if store.selectedTab?.isSettings == true {
                    BrowserSettings(store: store)
                } else if !store.visiblePages.isEmpty {
                    splitContent
                } else {
                    AddressPalette(store: store, standalone: true)
                }
                if store.showsSidebar {
                    BrowserSidebar(store: store)
                        .frame(height: max(0, geometry.size.height - SidebarGeometry.inset * 2))
                        .padding(SidebarGeometry.inset)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }
                if store.addressPresented {
                    CrestBrandTheme.canvas.opacity(0.3).onTapGesture { store.dismissAddress() }
                    AddressPalette(store: store)
                }
                if store.recentSwitcherPresented { BrowserRecentSwitcher(store: store) }
                if let notice = store.notice ?? store.owner.storageError {
                    Text(notice).font(.callout).padding(.horizontal, 16).padding(.vertical, 10)
                        .background(CrestBrandTheme.surface, in: Capsule())
                        .padding(.top, 12).frame(maxHeight: .infinity, alignment: .top)
                        .allowsHitTesting(false)
                }
            }
            .background(BrowserNativeWindowControlsBridge(isVisible: store.showsSidebar))
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: store.showsSidebar)
            .onHover { if !$0 { store.sidebarRevealed = false } }
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
        .tint(CrestBrandTheme.textDisplay)
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
                    Rectangle().stroke(CrestBrandTheme.line, lineWidth: 1).allowsHitTesting(false)
                }
            }
    }
}
