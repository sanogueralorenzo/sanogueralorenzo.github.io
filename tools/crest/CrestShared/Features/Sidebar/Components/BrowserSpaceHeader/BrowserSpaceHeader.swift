import SwiftUI

/// The Space's name, identity and actions menu.
///
/// One header for both shells. What used to be two files differing in a
/// handful of sizes is now one anatomy resolved from
/// `BrowserInteractionCapabilities`: the geometry comes from a metrics profile
/// and the menu from the closures the shell handed down.
struct BrowserSpaceHeader: View {
    let space: BrowserSpaceIdentity
    let isPrivateBrowsing: Bool
    let capabilities: BrowserInteractionCapabilities
    let actions: BrowserSpaceHeaderActions

    init(
        space: some BrowserSpaceIdentifying, isPrivateBrowsing: Bool,
        capabilities: BrowserInteractionCapabilities, actions: BrowserSpaceHeaderActions
    ) {
        self.space = space.identity
        self.isPrivateBrowsing = isPrivateBrowsing
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
        .padding(.horizontal, CrestSpacing.small)
    }

    private var title: some View {
        HStack(spacing: CrestSpacing.small) {
            BrowserSpaceIdentityIcon(identity: space, size: metrics.iconSize)

            Text(space.name)
                .font(.callout.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Spacer(minLength: CrestSpacing.small)
        }
        .frame(maxWidth: .infinity, maxHeight: metrics.contentMaxHeight, alignment: .leading)
        .accessibilityElement(children: .combine)
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
}

#if DEBUG
    #Preview("Saved tabs header") {
        BrowserSpaceHeader(
            space: BrowserSpaceIdentityPreviewFixture.simpleSpace, isPrivateBrowsing: false,
            capabilities: BrowserInteractionCapabilities(),
            actions: BrowserSpaceHeaderActions(openNewTab: {}, createFolder: {}, showHistory: {})
        )
        .padding().frame(width: 320)
    }
#endif
