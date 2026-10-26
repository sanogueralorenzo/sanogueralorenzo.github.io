import SwiftUI

struct MobileBrowserSidebarSpaceSurface: View {
    @Environment(\.colorScheme) private var colorScheme
    let configuration: MobileBrowserSidebarContentConfiguration
    let space: SpaceModel
    let isSelected: Bool

    var body: some View {

        MobileBrowserSidebarSpaceContent(
            configuration: configuration,
            space: space,
            isSelected: isSelected
        )
        .environment(\.colorScheme, spaceColorScheme)
        .blur(radius: 0)
        .redacted(reason: [])

        .accessibilityHidden(false)
        .overlay {
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(isSelected)
        .accessibilityHidden(!isSelected)
    }

    /// The sidebar reads its foreground from the Space's own branding rather
    /// than from the system appearance, as every compact placement does, so
    /// they keep agreeing.
    private var spaceColorScheme: ColorScheme {
        colorScheme
    }

    private func selectAvailableSpace(_ assignment: BrowserSpaceRuntimeAssignment) {
        guard
            let candidate = configuration.context.browser.spaceModel(matching: assignment)
        else { return }
        configuration.context.selectSpace(assignment.spaceID)
    }
}
