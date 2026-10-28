import SwiftUI

struct MobileSpaceActions: View {
    let browser: BrowserStore
    let pages: MobileBrowserPageStore
    let utilityPresentationStyle: MobileBrowserSidebarUtilityPresentationStyle
    let configuration: MobileSpaceActionsConfiguration

    var body: some View {
        HStack(spacing: 0) {
            MobileSpaceActionButtons(
                browser: browser,
                pages: pages,
                utilityPresentationStyle: utilityPresentationStyle,
                configuration: configuration
            )
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.plain)
        .controlSize(.large)
        .padding(4)
        .glassEffect(.regular, in: .capsule)
        .fixedSize(horizontal: true, vertical: false)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .frame(height: 60)
    }
}
