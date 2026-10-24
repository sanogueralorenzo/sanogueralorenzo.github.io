import SwiftUI

struct BrowserFolderDropIndicator: View {
    let location: BrowserFolderDropLocation
    let dragState: BrowserFolderDragState
    let isTargeted: Bool

    var body: some View {
        if isTargeted, dragState.dropLocation == location {
            Capsule()
                .fill(CrestColor.dropIndicator)
                .frame(height: 2)
                .padding(.horizontal, CrestSpacing.large)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}
