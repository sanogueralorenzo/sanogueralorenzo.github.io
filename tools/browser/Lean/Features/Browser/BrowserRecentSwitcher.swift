import SwiftUI

struct BrowserRecentSwitcher: View {
    let store: BrowserStore
    private var tabs: [BrowserTab] {
        store.recentTabIDs.compactMap { id in
            store.session.spaces.lazy.compactMap { $0.tabs.first { $0.id == id } }.first
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Recent Tabs").font(.headline).padding(8)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(Array(tabs.enumerated()), id: \.element.id) { index, tab in
                            HStack(spacing: 10) {
                                Image(systemName: "globe").frame(width: 20)
                                Text(tab.customTitle ?? tab.title).lineLimit(1)
                                Spacer()
                                if index == store.recentSwitcherIndex { Image(systemName: "return") }
                            }.padding(.horizontal, 10).frame(height: 40).background(
                                index == store.recentSwitcherIndex ? LeanBrandTheme.line : .clear,
                                in: RoundedRectangle(cornerRadius: LeanRadius.control)
                            )
                            .id(index).contentShape(Rectangle()).onTapGesture {
                                store.selectTab(tab.id)
                                store.recentSwitcherPresented = false
                            }
                        }
                    }
                }.frame(height: min(440, CGFloat(tabs.count) * 44))
                    .onChange(of: store.recentSwitcherIndex) {
                        proxy.scrollTo(store.recentSwitcherIndex, anchor: .center)
                    }
            }
        }.padding(12).frame(width: 440).background(
            LeanBrandTheme.surface, in: RoundedRectangle(cornerRadius: LeanRadius.panel))
    }
}

extension BrowserStore {
    func selectRecentTab(delta: Int) {
        if !recentSwitcherPresented {
            recentSwitcherIndex = 0
            recentSwitcherPresented = true
        }
        let ids = recentTabIDs
        guard !ids.isEmpty else { return }
        recentSwitcherIndex = (recentSwitcherIndex + delta + ids.count) % ids.count
    }

    func commitRecentTab() {
        let ids = recentTabIDs
        if ids.indices.contains(recentSwitcherIndex) { selectTab(ids[recentSwitcherIndex]) }
        recentSwitcherPresented = false
    }
}
