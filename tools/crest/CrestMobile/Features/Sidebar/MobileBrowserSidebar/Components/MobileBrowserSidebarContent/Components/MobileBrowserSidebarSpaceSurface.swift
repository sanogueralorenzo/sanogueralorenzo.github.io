import SwiftUI

struct MobileBrowserSidebarSpaceSurface: View {
    @Environment(\.colorScheme) private var colorScheme
    let configuration: MobileBrowserSidebarContentConfiguration
    let space: SpaceModel
    let isSelected: Bool

    var body: some View {
        let isLocked = configuration.context.spaceAccess.isLocked(space)

        MobileBrowserSidebarSpaceContent(
            configuration: configuration,
            space: space,
            isSelected: isSelected
        )
        .environment(\.colorScheme, spaceColorScheme)
        // Blur and redaction are drawing effects; rows still run their tasks.
        // This stops the ones that would otherwise disclose a locked Space's
        // hostnames to the network.
        .environment(\.browserSpaceContentIsLocked, isLocked)
        .blur(radius: isLocked ? BrowserSidebarMetrics.lockedSpaceBlurRadius : 0)
        .redacted(reason: isLocked ? .placeholder : [])
        .allowsHitTesting(!isLocked)
        .accessibilityHidden(isLocked)
        .overlay {
            if isLocked {
                BrowserSpaceAccessView(
                    space: space,
                    spaces: configuration.context.availableSpaces,
                    accessController: configuration.context.spaceAccess,
                    selectSpace: selectUnlockedSpace,
                    presentation: .contentOverlay
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(isSelected)
        .accessibilityHidden(!isSelected)
    }

    /// The sidebar reads its foreground from the Space's own branding rather
    /// than from the system appearance, as every compact placement does, so
    /// they keep agreeing.
    private var spaceColorScheme: ColorScheme {
        space.settings.look.colorScheme(over: colorScheme)
    }

    private func selectUnlockedSpace(_ assignment: BrowserSpaceRuntimeAssignment) {
        guard
            let candidate = configuration.context.browser.spaceModel(matching: assignment),
            !configuration.context.spaceAccess.isLocked(candidate)
        else { return }
        configuration.context.selectSpace(assignment.spaceID)
    }
}
