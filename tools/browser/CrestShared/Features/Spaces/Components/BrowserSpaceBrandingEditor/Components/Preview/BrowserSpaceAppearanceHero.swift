import SwiftUI

/// The same sidebar preview used by import and setup, dressed in the live draft.
struct BrowserSpaceAppearanceHero: View {
    @Environment(\.colorScheme) private var colorScheme
    let branding: SpaceBranding
    let symbol: String
    var name = ""
    var compact = false
    var editableName: Binding<String>? = nil
    var showsNameHint = false
    var spacePicker: BrowserSpaceCustomizationPicker? = nil
    @State private var favicons = FaviconAssets()

    /// The showcase's first Space dressed in the draft, as the core resolves it.
    private var preview: SpaceModel {
        SpaceModel.detached(
            SessionState.Seed.showcase.spaces[0].wearing(
                branding, symbol: symbol, name: name.isEmpty ? String(localized: "Your Space") : name))
    }

    private var nameHint: LocalizedStringKey {
        #if os(iOS)
            "Tap the name to rename"
        #else
            "Click the name to rename"
        #endif
    }

    var body: some View {
        let preview = preview
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                BrowserSpaceIdentityIcon(space: preview, size: 26)
                    .frame(width: 26, height: 26)
                if let editableName {
                    BrowserInlineSpaceName(
                        name: editableName, size: 16,
                        titleFont: CrestTypography.sans(16, weight: .semibold))
                } else {
                    Text(preview.settings.name).font(CrestTypography.sans(16, weight: .semibold)).lineLimit(1)
                    Spacer()
                }
            }
            .padding(.horizontal, 14)
            .frame(height: BrowserSpaceSwitcherLayout.compactStripHeight)
            if showsNameHint {
                Text(nameHint)
                    .font(CrestTypography.sans(11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 14)
            }
            if !compact {
                BrowserSpaceSidebarPreview(space: preview)
            } else {
                #if os(iOS)
                    BrowserSpaceSidebarTabRow(
                        tab: Self.exampleTab, favicons: favicons, profileID: preview.profileID, isSelected: true
                    )
                    .font(.subheadline)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 18)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                #else
                    let assignment = BrowserSpaceRuntimeAssignment(space: preview)
                    PinnedTabGrid(
                        tabs: preview.pinnedTabs, favicons: favicons, assignment: assignment, select: { _ in }
                    )
                    .padding(.horizontal, 14).padding(.bottom, 12)
                    .allowsHitTesting(false)
                #endif
            }
            if let spacePicker {
                spacePicker
            }
        }
        .background { BrowserSpaceBannerBackground(branding: branding) }
        .environment(\.colorScheme, branding.colorScheme(over: colorScheme))
        .environment(\.sidebarSpacePresentation, SidebarSpacePresentation(space: preview, isUnlocked: true))
        .clipShape(.rect(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18).strokeBorder(.primary.opacity(0.12))
        }
        .shadow(color: .black.opacity(0.12), radius: 16, y: 8)
        .accessibilityElement(children: editableName == nil && spacePicker == nil ? .ignore : .contain)
        .accessibilityLabel("Live sidebar preview for \(preview.settings.name)")
    }

    /// The tab a compact preview shows under the name: a Start Page.
    @MainActor private static let exampleTab = SpaceModel.detached(
        SpaceState.Seed(name: String(localized: "Your Space"), tabs: [.startPage()])
    ).tabs.models[0]
}

#if DEBUG
    #Preview("Editable Space identity") {
        @Previewable @State var name = "Work"
        BrowserSpaceAppearanceHero(
            branding: BrowserSpaceBrandingPreviewFixture.crestBranding, symbol: "crown.fill", name: name,
            editableName: $name, showsNameHint: true
        )
        .frame(width: 420, height: 440)
    }
#endif
