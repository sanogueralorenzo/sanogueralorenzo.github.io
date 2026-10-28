import SwiftUI

struct BrowserSidebarItem: View {
    let tab: BrowserTab
    let store: BrowserStore
    var pinned = false
    var depth = 0

    var body: some View {
        if let split = store.activeSpace.splits.first(where: { $0.tabIDs.contains(tab.id) }) {
            if split.tabIDs.first == tab.id {
                VStack(spacing: 0) {
                    splitHeader(split)
                    ForEach(split.tabIDs, id: \.self) { id in
                        if let member = store.activeSpace.tabs.first(where: { $0.id == id }) {
                            BrowserTabRow(tab: member, store: store, pinned: pinned, depth: depth + 1)
                                .padding(.vertical, 1)
                        }
                    }
                }
                .padding(4)
                .background(
                    Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: max(0, 20 - CGFloat(depth) * 4))
                )
                .contextMenu { splitActions(split) }
                .modifier(
                    BrowserSidebarReorderItem(
                        store: store, id: split.id, placement: tab.placement, folderID: tab.folderID))
            }
        } else {
            BrowserTabRow(tab: tab, store: store, pinned: pinned, depth: depth)
        }
    }

    private func splitHeader(_ split: BrowserSplit) -> some View {
        HStack(spacing: 7) {
            ZStack {
                ForEach(Array(split.tabIDs.prefix(3).enumerated()), id: \.element) { index, id in
                    if let member = store.activeSpace.tabs.first(where: { $0.id == id }) {
                        TabIcon(tab: member).scaleEffect(0.65).background(LeanBrandTheme.surface, in: Circle())
                            .rotationEffect(.degrees(Double(index - 1) * 3.5)).offset(x: CGFloat(index - 1) * 4)
                    }
                }
            }.frame(width: 23, height: 16)
            Button {
                guard !store.owner.suppressesSidebarActivation else { return }
                store.selectTab(split.tabIDs.contains(store.selectedTab?.id ?? UUID()) ? store.selectedTab!.id : tab.id)
            } label: {
                Text(
                    split.tabIDs.compactMap { id in
                        store.activeSpace.tabs.first { $0.id == id }.map { $0.customTitle ?? $0.title }
                    }.joined(separator: " / ")
                )
                .font(.caption.weight(.semibold)).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
            }.buttonStyle(.plain)
            Menu {
                splitActions(split)
            } label: {
                Image(systemName: "ellipsis").frame(width: 30, height: 30)
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().accessibilityLabel("Split View actions")
        }
        .frame(height: 30).padding(.horizontal, 9)
        .modifier(
            BrowserSidebarDragSource(
                store: store, payload: { store.dragPayload(split: split) }, title: tab.customTitle ?? tab.title,
                url: tab.url)
        )
        .accessibilityElement(children: .contain).accessibilityValue("Split View with \(split.tabIDs.count) tabs")
    }

    @ViewBuilder private func splitActions(_ split: BrowserSplit) -> some View {
        Button("Change Split Direction") {
            store.selectTab(tab.id)
            store.changeSplitDirection()
        }
        Button("Separate All Tabs") {
            store.selectTab(tab.id)
            store.leaveSplit()
        }
        Divider()
        if tab.placement == .current {
            Button("Close Split", role: .destructive) { store.requestDeleteTabs(split.tabIDs) }
        }
    }
}
