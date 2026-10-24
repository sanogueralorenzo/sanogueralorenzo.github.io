import SwiftUI

struct MobileBrowserSidebarContent: View {
    let configuration: MobileBrowserSidebarContentConfiguration

    var body: some View {
        if #available(iOS 27.0, *) {
            MobileBrowserSidebarLayout(configuration: configuration)
        } else {
            MobileBrowserSidebarLayout(configuration: configuration)
                .gesture(
                    MobileDragReleaseGesture {
                        configuration.context.sidebarInteraction.tabDragState
                            .endAfterTouchRelease()
                        configuration.context.sidebarInteraction.folderDragState
                            .endAfterTouchRelease()
                    }
                )
        }
    }
}
