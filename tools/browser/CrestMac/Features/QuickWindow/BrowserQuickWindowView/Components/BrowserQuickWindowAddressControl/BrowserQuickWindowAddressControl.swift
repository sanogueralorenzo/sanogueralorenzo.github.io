import SwiftUI

struct BrowserQuickWindowAddressControl: View {
    let model: BrowserQuickWindowModel
    @Binding var addressText: String
    @Binding var isAddressEditing: Bool
    let addressFocusRequest: Int

    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        HStack(spacing: 7) {
            BrowserQuickWindowSourceSpaceIndicator(space: model.spaceModel?.identity)
            Divider().frame(height: 16)
            BrowserQuickWindowAddressSecurityIcon(
                isSecure: model.page?.live.security.isSecure == true
            )
            BrowserAddressContent(
                text: $addressText,
                isEditing: $isAddressEditing,
                focusRequest: addressFocusRequest,
                activate: nil,
                editorAccessibilityLabel: "Quick Window address",
                editorAccessibilityIdentifier: "quick-window-address",
                summaryAccessibilityIdentifier: "quick-window-address-display",
                prompt: "Search or enter a website",
                submit: openAddress
            )
            .padding(.vertical, BrowserQuickWindowLayout.addressVerticalPadding)
            BrowserQuickWindowAddressTrailingControl(
                page: model.page,
                addressText: $addressText,
                isAddressEditing: isAddressEditing,
                reloadOrStop: reloadOrStop
            )
        }
        .browserAddressFieldSurface(
            leadingPadding: BrowserQuickWindowLayout.sourceChipLeadingInset,
            progress: model.page?.estimatedProgress ?? 0,
            isLoading: model.page?.live.isLoading == true,
            isEditing: isAddressEditing
        )
        .frame(
            minWidth: BrowserQuickWindowLayout.addressMinimumWidth,
            maxWidth: .infinity
        )
    }

    private func openAddress() {
        guard let space = model.spaceModel,
            let resolved = try? model.browser.core.query(
                ResolveAddress(workspaceID: model.browser.family.workspaceID, spaceID: space.id, input: addressText)),
            let url = resolved.url.flatMap(URL.init(string:))
        else { return }
        addressText = url.absoluteString
        model.open(url, isActive: scenePhase == .active)
    }

    private func reloadOrStop() {
        model.recordUserActivity()
        model.page?.performReload(.standard)
    }
}
