import AppKit
import SwiftUI

/// A Space's Appearance page: the Crest Studio's Forge beside the window's
/// live sidebar, or the studio with its own preview where Settings can't show
/// that sidebar.
struct BrowserSpaceEditorView: View {
    @Environment(\.browserSettingsUsesLiveSidebar) private var usesLiveSidebar
    @Environment(\.browserSettingsTabState) private var tabState
    @State private var standaloneScroll = BrowserNativeScrollState()
    @State private var standaloneStep = BrowserCrestStudioStep.shape

    private var scrollState: BrowserNativeScrollState {
        tabState?.scroll(forKey: "space-\(space.id)-appearance") ?? standaloneScroll
    }

    let browser: BrowserStore
    let space: SpaceModel

    var body: some View {
        Group {
            if usesLiveSidebar {
                BrowserCrestForge(branding: branding, symbol: symbol, step: forgeStep)
            } else {
                appearanceEditor
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("space-customization-controls")
    }

    private var appearanceEditor: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width >= 620
            let dense = geometry.size.height < 640
            HStack(alignment: .top, spacing: 0) {
                if wide {
                    VStack(spacing: 16) {
                        BrowserCrestStudioPreview(
                            branding: branding.wrappedValue, symbol: symbol.wrappedValue,
                            name: space.settings.name, space: BrowserSpaceAppearance(space: space),
                            heroSize: geometry.size.height < 480 ? 96 : 140,
                            sidebarHeight: max(100, min(230, geometry.size.height - 300)))
                        Spacer(minLength: 0)
                    }
                    .frame(width: min(280, geometry.size.width * 0.32))
                    .padding(14)
                }
                ScrollView {
                    BrowserSpaceBrandingEditor(
                        branding: branding, symbol: symbol, previewName: space.settings.name,
                        compact: !wide, showsPreview: !wide, editableName: name
                    )
                    .id(space.id)
                    .padding(dense ? 14 : 20)
                    .frame(maxWidth: 680, alignment: .leading)
                    .frame(maxWidth: .infinity)
                }
                .browserNativeScrollState(scrollState)
                .contentMargins(.trailing, 12, for: .scrollContent)
                .defaultScrollAnchor(.top, for: .initialOffset)
            }
        }
    }

    private var forgeStep: Binding<BrowserCrestStudioStep> {
        Binding(
            get: { tabState?.forgeStep ?? standaloneStep },
            set: { if let tabState { tabState.forgeStep = $0 } else { standaloneStep = $0 } })
    }

    private var name: Binding<String> {
        browser.spaceNameBinding(in: space)
    }

    private var symbol: Binding<String> {
        browser.spaceSymbolBinding(in: space)
    }

    private var branding: Binding<SpaceBranding> {
        browser.spaceBrandingBinding(in: space)
    }
}
