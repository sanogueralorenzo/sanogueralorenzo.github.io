import SwiftUI

/// The content seam used by both single cards and Split View, on every shell.
/// The surrounding layout owns identity, geometry, focus, and placement.
struct BrowserNativeTabHost: View {
    let tab: TabStateModel
    let space: SpaceModel
    /// The shell's floating controls remain outside native scrolling content.
    var bottomChromeHeight: CGFloat = 0
    @Environment(\.browserSettingsTabContent) private var settingsContent
    @Environment(\.browserNativeTabs) private var nativeTabs

    var body: some View {
        Group {
            if let content = tab.nativeTabContent,
                let runtime = nativeTabs?.runtime(matching: assignment, content: content)
            {
                switch tab.nativeView {
                case .settings?:
                    if let settingsContent {
                        settingsContent.makeView(runtime)
                    } else {
                        ContentUnavailableView("Settings unavailable", systemImage: "gearshape")
                    }
                default:
                    ContentUnavailableView(
                        "This tab needs a newer Crest", systemImage: "square.stack.3d.up",
                        description: Text("Its content is still saved. Update Crest to open it.")
                    )
                }
            }
        }
        .id(tab.nativeTabContent.flatMap { nativeTabs?.runtime(matching: assignment, content: $0)?.id })
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .safeAreaPadding(.bottom, bottomChromeHeight)
    }

    private var assignment: BrowserTabRuntimeAssignment {
        BrowserTabRuntimeAssignment(tabID: tab.id, spaceID: space.id, profileID: space.profileID)
    }
}
