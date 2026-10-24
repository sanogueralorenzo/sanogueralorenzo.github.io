import SwiftUI

/// A Space no window shows, as its sidebar would draw it: a preview, a setup
/// draft or an import under review.
struct BrowserSpaceSidebarPreview: View {
    let space: SpaceModel
    /// The images the Space's tabs wear. A draft or a preview wears none.
    var favicons = FaviconAssets()
    @Environment(\.browserInteractionCapabilities) private var capabilities
    @Environment(\.colorScheme) private var colorScheme
    @Environment(CrestCore.self) private var core: CrestCore?

    /// No window shows a previewed Space, so it highlights the tab the core
    /// would show first.
    private var selectedTabID: UUID? { core?.fallbackTabID(in: space) }

    private var branding: SpaceBranding { space.settings.look }

    var body: some View {
        let branding = branding
        ZStack {
            BrowserSpaceBannerBackground(branding: branding)

            VStack(spacing: 0) {
                HStack(
                    spacing: BrowserManualSetupSidebarPreviewMetrics.addressSpacing
                ) {
                    Image(systemName: "magnifyingglass")
                    Text("Search or enter website")
                        .lineLimit(1)
                    Spacer()
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(
                    .horizontal,
                    BrowserManualSetupSidebarPreviewMetrics
                        .addressHorizontalPadding
                )
                .frame(
                    height: BrowserManualSetupSidebarPreviewMetrics.addressHeight
                )
                .browserAddressFieldSurface(progress: 0, isLoading: false, isEditing: false, branding: branding)
                .padding(
                    BrowserManualSetupSidebarPreviewMetrics.addressOuterPadding
                )

                ScrollView {
                    VStack(
                        alignment: .leading,
                        spacing: BrowserManualSetupSidebarPreviewMetrics
                            .contentSpacing
                    ) {
                        if !space.pinnedTabs.isEmpty {
                            PinnedTabGrid(
                                tabs: space.pinnedTabs, favicons: favicons,
                                assignment: BrowserSpaceRuntimeAssignment(space: space),
                                selectedTabID: selectedTabID, select: { _ in }, capabilities: capabilities
                            )
                        }
                        BrowserSpaceSidebarSection(
                            title: "SAVED",
                            tabs: space.unfiledSavedTabs,
                            favicons: favicons,
                            profileID: space.profileID,
                            selectedTabID: selectedTabID
                        )
                        BrowserSpaceSidebarSection(
                            title: "OPEN TABS",
                            tabs: space.currentTabs,
                            favicons: favicons,
                            profileID: space.profileID,
                            selectedTabID: selectedTabID
                        )
                    }
                    .padding(
                        .horizontal,
                        BrowserManualSetupSidebarPreviewMetrics
                            .contentHorizontalPadding
                    )
                    .padding(
                        .bottom,
                        BrowserManualSetupSidebarPreviewMetrics
                            .contentBottomPadding
                    )
                }
            }
        }
        .clipShape(
            .rect(
                cornerRadius: BrowserManualSetupSidebarPreviewMetrics
                    .frameCornerRadius,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: BrowserManualSetupSidebarPreviewMetrics
                    .frameCornerRadius,
                style: .continuous
            )
            .strokeBorder(
                Color.primary.opacity(
                    BrowserManualSetupSidebarPreviewMetrics.frameStrokeOpacity
                ),
                lineWidth: BrowserManualSetupSidebarPreviewMetrics
                    .frameStrokeWidth
            )
        }
        .environment(
            \.colorScheme,
            branding.colorScheme(over: colorScheme)
        )
        .allowsHitTesting(false)
        .environment(\.sidebarSpacePresentation, SidebarSpacePresentation(space: space, isUnlocked: true))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Branding preview of \(space.settings.name)")
        .accessibilityValue(accessibilitySummary)
    }

    private var accessibilitySummary: String {
        let branding = branding
        let colors = branding.colors.map { String(localized: $0.title) }.joined(separator: ", ")
        return
            "\(String(localized: branding.themeMode.title)), \(colors), \(String(localized: branding.iconStyle.title))"
    }
}
