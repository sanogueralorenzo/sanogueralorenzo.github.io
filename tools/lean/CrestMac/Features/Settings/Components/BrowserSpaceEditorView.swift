import SwiftUI

struct BrowserSpaceEditorView: View {
    let browser: BrowserStore
    let space: SpaceModel
    let dataDeleter: any BrowserSpaceDataDeleting
    var requestsEditing: Binding<Bool> = .constant(false)

    var body: some View {
        BrowserSettingsPane(.spaces) {
            Section("Identity") {
                BrowserSpaceIdentityEditor(
                    name: browser.spaceNameBinding(in: space), color: browser.spaceColorBinding(in: space),
                    requestsEditing: requestsEditing)
            }
            BrowserSpaceDeletionSection(browser: browser, spaceID: space.id, dataDeleter: dataDeleter)
        }
    }
}
