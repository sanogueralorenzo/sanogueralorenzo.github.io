import SwiftUI

/// The production artwork and sidebar components, detached from browsing and persistence.
struct BrowserCrestStudioPreview: View {
    let branding: SpaceBranding
    let symbol: String
    var name: String = ""
    var space: BrowserSpaceAppearance? = nil
    var compact = false
    var showsSidebar = true
    var heroSize: CGFloat = 140
    var sidebarHeight: CGFloat = 190

    private var preview: BrowserSpaceAppearance {
        (space ?? .studioSample).wearing(
            branding, symbol: symbol, name: name.isEmpty ? String(localized: "Your Space") : name)
    }

    @Environment(\.browserInteractionCapabilities) private var capabilities
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 8) {
                BrowserSpaceIdentityIcon(identity: preview.identity, size: compact ? 96 : heroSize)
                Text(preview.identity.name).font(.headline).lineLimit(1)
            }
            .padding(20)
            .frame(maxWidth: .infinity)
            .background { BrowserSpaceBannerBackground(branding: branding) }
            .environment(\.colorScheme, branding.colorScheme(over: colorScheme))
            .clipShape(.rect(cornerRadius: 18))

            if !compact && showsSidebar {
                VStack(spacing: 4) {
                    BrowserLookAndFeelAddressPreview(space: preview, showsBackground: false)
                        .padding(.horizontal, 8).padding(.top, 10)
                    BrowserSpaceHeader(
                        space: preview.identity, isPrivateBrowsing: false, isSavedTabsExpanded: .constant(true),
                        capabilities: BrowserInteractionCapabilities(
                            supportsTouch: capabilities.supportsTouch,
                            pairsRowWithPromotedSurface: false, supportsOrganization: false),
                        actions: BrowserSpaceHeaderActions(
                            openNewTab: {}, createFolder: {}, showHistory: {}, cleanup: {}))
                    BrowserSidebarCustomizationPreview(
                        space: preview, showsPins: false, showsCurrentTabs: false, showsBackground: false)
                }
                .frame(height: sidebarHeight, alignment: .top)
                .clipped()
                .background { BrowserSpaceBannerBackground(branding: branding) }
                .environment(\.colorScheme, branding.colorScheme(over: colorScheme))
                .clipShape(.rect(cornerRadius: 16))
                .allowsHitTesting(false)
                .accessibilityLabel("Actual sidebar preview")
            }
            Text("Changes appear live in your Space.").font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

struct BrowserCrestStudioMark: View {
    let branding: SpaceBranding
    let symbol: String
    var size: CGFloat
    var body: some View {
        BrowserSpaceIdentityIcon(
            identity: BrowserSpaceAppearance.studioSample.identity.wearing(
                branding, symbol: symbol, name: BrowserSpaceAppearance.studioSample.identity.name),
            size: size)
    }
}

extension BrowserSpaceAppearance {
    /// The Space the studio dresses in the look being edited when it edits no
    /// Space of its own: the showcase's first Space.
    @MainActor static let studioSample = BrowserSpaceAppearance(
        space: SpaceModel.detached(SessionState.Seed.showcase.spaces[0]))
}

#if DEBUG
    #Preview("Component") {
        BrowserCrestStudioPreview(
            branding: BrowserSpaceBrandingPreviewFixture.crestBranding, symbol: "crown.fill", name: "Work"
        ).padding().frame(width: 420, height: 580)
    }
#endif
