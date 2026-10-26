import SwiftUI

struct MobileSpaceSelectionSection: View {
    let browser: BrowserStore
    @Binding var selectedSpaceID: UUID?

    var body: some View {
        Section("Space") {
            Picker("Edit", selection: $selectedSpaceID) {
                ForEach(browser.spaceModels) { space in
                    BrowserSpaceIdentityLabel(space: space)
                        .tag(Optional(space.id))
                }
            }

            HStack {
                Text("Order")
                Spacer()
                BrowserSpaceOrderControls(browser: browser, spaceID: selectedSpaceID)
                BrowserSpaceAddButton {
                    browser.addSpace()
                    selectedSpaceID = browser.selectedSpaceID
                }
            }
        }
    }
}
