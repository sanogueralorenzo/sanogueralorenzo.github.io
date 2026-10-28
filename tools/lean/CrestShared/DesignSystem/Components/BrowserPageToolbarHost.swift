import SwiftUI

/// One top inset for every page bar. Callers register views in stacking order
/// and conditionally include them; SwiftUI retains each surviving bar's identity.
/// Page services belong on the page outside this host so hiding chrome never
/// tears down a translation session, web view, or developer operation.
struct BrowserPageToolbarHost<Bars: View>: ViewModifier {
    @ViewBuilder let bars: () -> Bars

    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 0, content: bars)
                .frame(maxWidth: .infinity)
        }
    }
}

/// Common geometry, separator, and accessibility for a docked page toolbar.
/// A feature supplies only its controls and its own background treatment.
struct BrowserPageToolbarSurface<Controls: View, Background: View>: View {
    let label: LocalizedStringKey
    let identifier: String
    @ViewBuilder let controls: () -> Controls
    @ViewBuilder let background: () -> Background

    var body: some View {
        controls()
            .frame(minHeight: controlHeight)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(content: background)
            .overlay(alignment: .bottom) { Divider() }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text(label))
            .accessibilityIdentifier(identifier)
    }

    private var controlHeight: CGFloat {
        #if os(macOS)
            28
        #else
            44
        #endif
    }
}
