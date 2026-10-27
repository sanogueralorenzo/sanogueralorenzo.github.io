import SwiftUI

/// The unoccupied remainder moves the window; a double-click opens a tab.
struct BrowserSidebarBackground: View {
    let store: BrowserStore
    var body: some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(WindowDragGesture())
            .simultaneousGesture(TapGesture(count: 2).onEnded { store.presentAddress(newTab: true) })
            .allowsWindowActivationEvents()
            .accessibilityLabel("Sidebar background")
            .accessibilityHint("Drag to move the window")
            .contextMenu {
                Button("New Tab") { store.presentAddress(newTab: true) }
                Button("New Folder") { store.addFolder() }
            }
    }
}
