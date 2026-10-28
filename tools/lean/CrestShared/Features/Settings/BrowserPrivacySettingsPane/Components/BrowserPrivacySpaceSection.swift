import SwiftUI

struct BrowserPrivacySpaceSection: View {
    @Binding var selectedSpaceID: UUID?
    let spaces: [SpaceModel]

    var body: some View {
        Section {
            CrestSpaceMenuPicker(
                "Space",
                selection: $selectedSpaceID,
                spaces: CrestSpaceIdentity.list(spaces)
            )
        }
    }
}

#if DEBUG
    #Preview("Space selection") {
        @Previewable @State var browser = BrowserStore(seed: .preview)
        @Previewable @State var selection: UUID? = SessionState.Seed.preview.spaces[0].id
        Form { BrowserPrivacySpaceSection(selectedSpaceID: $selection, spaces: browser.spaceModels) }
            .crestSettingsForm().frame(width: 420, height: 220)
    }
#endif
