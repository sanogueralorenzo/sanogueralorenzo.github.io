import SwiftUI

/// Which engine the site opens in, shown when this device registered more
/// than one. Choosing another moves the page there, which loads what it
/// showed, and the site's later pages open there too.
struct BrowserSiteEngineRow: View {
    let page: BrowserPage
    let origin: SiteOrigin

    var body: some View {
        if let engines = page.corePage.engines?.engines, engines.count > 1, let current = page.corePage.state?.engine {
            Picker("Opens in", selection: selection(current)) {
                ForEach(engines, id: \.kind) { engine in
                    Label {
                        Text(engine.kind.title)
                    } icon: {
                        BrowserSiteEngineMenuIcon(mark: engine.kind.mark)
                    }
                    .tag(engine.kind)
                }
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("site-engine-picker")
        }
    }

    private func selection(_ current: EngineKind) -> Binding<EngineKind> {
        Binding(
            get: { current },
            set: { engine in
                guard engine != current else { return }
                page.corePage.open(origin, in: page.spaceID, on: engine)
            })
    }
}
