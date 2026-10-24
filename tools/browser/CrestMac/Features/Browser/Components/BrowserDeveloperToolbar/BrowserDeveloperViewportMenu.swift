import SwiftUI

struct BrowserDeveloperViewportMenu: View {
    let page: BrowserPage
    @State private var showsCustomSize = false
    @State private var showsCustomSizeEditor = false
    @State private var width = ""
    @State private var height = ""

    /// A choice in the viewport picker, which is also the picker's tag.
    private enum Selection: Hashable {
        case normal
        case preset(BrowserDeveloperViewport)
        case custom

        /// Shows the choice on the menu's page.
        @MainActor
        func apply(to menu: BrowserDeveloperViewportMenu) {
            switch self {
            case .normal:
                menu.showsCustomSize = false
                menu.page.developerViewport = nil
            case .preset(let viewport):
                menu.showsCustomSize = false
                menu.page.developerViewport = viewport
            case .custom:
                if !menu.showsCustomSize { menu.populateCustomSize() }
                menu.showsCustomSize = true
                menu.showsCustomSizeEditor = true
            }
        }
    }

    var body: some View {
        viewportMenu
            .popover(isPresented: $showsCustomSizeEditor, arrowEdge: .top) {
                BrowserDeveloperCustomViewportFields(width: $width, height: $height) {
                    guard let viewport = BrowserDeveloperViewport.customSize(width: width, height: height) else {
                        return
                    }
                    page.developerViewport = viewport
                }
                .padding(12)
            }
            .onAppear(perform: synchronizeCustomSize)
            .onChange(of: page.developerViewport) { _, _ in
                synchronizeCustomSize()
            }
    }

    private var viewportMenu: some View {
        Menu {
            Picker(
                "Viewport",
                selection: Binding(
                    get: {
                        if showsCustomSize { return Selection.custom }
                        return page.developerViewport.map(Selection.preset) ?? .normal
                    },
                    set: { selection in
                        selection.apply(to: self)
                    }
                )
            ) {
                Label("Normal — Preview Off", systemImage: "rectangle")
                    .tag(Selection.normal)
                ForEach(BrowserDeveloperViewport.presets) { viewport in
                    Label("\(viewport.title) — \(viewport.dimensions)", systemImage: viewport.symbol)
                        .tag(Selection.preset(viewport))
                }
                Label("Custom", systemImage: "ruler")
                    .tag(Selection.custom)
            }
            .pickerStyle(.inline)
        } label: {
            Label("Viewport Preview", systemImage: "macbook.and.iphone")
                .labelStyle(.iconOnly)
                .frame(height: BrowserDeveloperToolbarMetrics.buttonSize)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .foregroundStyle(page.developerViewport == nil ? Color.primary : Color.accentColor)
        .help("Viewport Preview")
        .accessibilityLabel("Viewport Preview")
        .accessibilityValue(
            showsCustomSize
                ? String(localized: "Custom")
                : page.developerViewport.map { String(localized: $0.title) } ?? String(localized: "Off")
        )
        .accessibilityIdentifier("developer-viewport-menu")
    }

    private func synchronizeCustomSize() {
        showsCustomSize = page.developerViewport?.isCustom == true
        if showsCustomSize { populateCustomSize() }
    }

    private func populateCustomSize() {
        let size = page.developerViewport?.size ?? page.viewportSize
        width = String(Int(size.width.rounded()))
        height = String(Int(size.height.rounded()))
    }
}
