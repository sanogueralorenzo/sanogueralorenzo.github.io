import SwiftUI

/// The menu for the group as a whole: the two ways a split ends.
///
/// Everything that belongs to one pane rather than to the run — moving a member
/// along the carousel, taking it out of the split, and every ordinary tab
/// action beside them — is on the member row's own menu, so there is one place
/// that owns tab organization and one that owns the group.
struct BrowserSidebarSplitGroupContextMenu: View {

    let configuration: BrowserSidebarSplitGroupRowConfiguration
    let interaction: BrowserSidebarSplitGroupRowInteractionContext

    var body: some View {
        Group {
            if let first = configuration.members.first,
                let request = BrowserSidebarSelection.capture(for: .tab(first.id), in: configuration.browser)
            {
                BrowserTabBatchMenu(
                    request: request, browser: configuration.browser,
                    spaceAccess: configuration.spaceAccess, unload: { configuration.context.unload($0) })
            } else {
                Button("Rename Split View…", systemImage: "pencil") {
                    interaction.beginRenaming()
                }
                .disabled(!configuration.isAvailableForDisplay)

                Button("Change Icon…", systemImage: "face.smiling") {
                    interaction.beginChangingIcon()
                }
                .disabled(!configuration.isAvailableForDisplay)

                Button("Change Color…", systemImage: "paintpalette") {
                    interaction.beginChangingTint()
                }
                .disabled(!configuration.isAvailableForDisplay)

                Divider()

                Button("Separate All Tabs", systemImage: "rectangle.split.2x1.slash") {
                    guard configuration.isCurrentAndUnlocked,
                        let first = configuration.members.first
                    else { return }
                    configuration.browser.dissolveSplit(
                        containing: first.id,
                        matching: configuration.assignment
                    )
                }
                .disabled(!configuration.isAvailableForDisplay)

                if configuration.canClose {
                    Divider()

                    Button("Close Split", systemImage: "xmark", role: .destructive) {
                        interaction.closeSplit()
                    }
                    .disabled(!configuration.isAvailableForDisplay)
                }
            }
        }
        .crestMenuActionLabelStyle()
    }
}
