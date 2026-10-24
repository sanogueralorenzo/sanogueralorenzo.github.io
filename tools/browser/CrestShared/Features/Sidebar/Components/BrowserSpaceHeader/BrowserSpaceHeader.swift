import SwiftUI

/// The Space's name and identity, the disclosure that opens its saved tabs,
/// and the menu of everything the shell can do to it.
///
/// One header for both shells. What used to be two files differing in a
/// handful of sizes is now one anatomy resolved from
/// `BrowserInteractionCapabilities`: the geometry comes from a metrics profile
/// and the menu from the closures the shell handed down.
struct BrowserSpaceHeader: View {
    let space: BrowserSpaceIdentity
    let isPrivateBrowsing: Bool
    @Binding var isSavedTabsExpanded: Bool
    let capabilities: BrowserInteractionCapabilities
    let actions: BrowserSpaceHeaderActions

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        space: some BrowserSpaceIdentifying, isPrivateBrowsing: Bool, isSavedTabsExpanded: Binding<Bool>,
        capabilities: BrowserInteractionCapabilities, actions: BrowserSpaceHeaderActions
    ) {
        self.space = space.identity
        self.isPrivateBrowsing = isPrivateBrowsing
        _isSavedTabsExpanded = isSavedTabsExpanded
        self.capabilities = capabilities
        self.actions = actions
    }

    var body: some View {
        heightConstrained(
            HStack(spacing: 0) {
                title

                BrowserSpaceHeaderActionsMenu(
                    isPrivateBrowsing: isPrivateBrowsing,
                    metrics: metrics,
                    actions: actions
                )
            }
            .padding(.leading, CrestSpacing.small)
            .padding(.trailing, CrestSpacing.extraSmall)
        )
        .crestHoverSurface(
            cornerRadius: CrestLayout.sidebarControlCornerRadius
        )
        .padding(.horizontal, CrestSpacing.small)
    }

    private var title: some View {
        Button(action: toggleSavedTabs) {
            HStack(spacing: CrestSpacing.small) {
                identity

                Text(space.name)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                if space.requiresAuthentication {
                    Image(systemName: "lock.fill")
                        .font(.caption2.weight(.bold))
                        .accessibilityLabel("Private Space")
                }

                Spacer(minLength: CrestSpacing.small)
            }
            .frame(
                maxWidth: .infinity,
                maxHeight: metrics.contentMaxHeight,
                alignment: .leading
            )
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(space.name) saved tabs")
        .accessibilityValue(isSavedTabsExpanded ? "Expanded" : "Collapsed")
        .accessibilityHint(
            isSavedTabsExpanded
                ? "Collapses saved tabs"
                : "Expands saved tabs"
        )
    }

    /// The Space's crest, swapped for a chevron while the saved tabs are
    /// closed — the two share one slot so the title never shifts sideways as
    /// the section opens.
    private var identity: some View {
        Group {
            if !isSavedTabsExpanded {
                Image(systemName: "chevron.right")
                    .font(
                        .system(
                            size: metrics.disclosureGlyphSize,
                            weight: .bold
                        )
                    )
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            } else {
                BrowserSpaceIdentityIcon(identity: space, size: metrics.iconSize)
                    .transition(.opacity)
            }
        }
        .frame(width: metrics.iconSize, height: metrics.iconSize)
    }

    /// A fixed band where the shell holds every row to one height, and a floor
    /// where the row is allowed to grow with its label instead.
    @ViewBuilder
    private func heightConstrained(_ content: some View) -> some View {
        if metrics.fillsRowHeight {
            content.frame(height: CrestLayout.sidebarRowHeight)
        } else {
            content.frame(minHeight: CrestLayout.sidebarRowHeight)
        }
    }

    private var metrics: BrowserSpaceHeaderMetrics {
        capabilities.spaceHeaderMetrics
    }

    private func toggleSavedTabs() {
        withAnimation(
            CrestMotion.disclosure.unlessReducingMotion(reduceMotion)
        ) {
            if let toggle = actions.toggleSavedTabs {
                toggle()
            } else {
                isSavedTabsExpanded.toggle()
            }
        }
    }
}

#if DEBUG
    #Preview("Saved tabs header") {
        @Previewable @State var expanded = true
        BrowserSpaceHeader(
            space: BrowserSpaceBrandingPreviewFixture.simpleSpace, isPrivateBrowsing: false,
            isSavedTabsExpanded: $expanded, capabilities: BrowserInteractionCapabilities(),
            actions: BrowserSpaceHeaderActions(openNewTab: {}, createFolder: {}, showHistory: {}, cleanup: {})
        )
        .padding().frame(width: 320)
    }
#endif
