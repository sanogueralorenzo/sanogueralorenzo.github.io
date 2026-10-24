import SwiftUI

struct BrowserQuickWindowPageObservationModifier: ViewModifier {
    let model: BrowserQuickWindowModel
    @Binding var addressText: String
    let isAddressEditing: Bool

    func body(content: Content) -> some View {
        content
            .onChange(of: model.page?.live.documentURL) { _, url in
                guard let url else { return }
                addressText = url.absoluteString
                model.updatePresentedURL(url)
            }
            // An address typed and then dismissed gives the field back to
            // the page.
            .onChange(of: isAddressEditing) { _, isEditing in
                guard !isEditing else { return }
                addressText = model.address
            }
            .onChange(of: addressText) {
                model.recordUserActivity()
            }
    }
}
