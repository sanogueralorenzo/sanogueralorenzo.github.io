import SwiftUI
import UIKit

struct MobileSpaceSettingsView: View {
    @Environment(\.browserSettingsUsesLiveSidebar) private var usesLiveSidebar
    @Environment(\.browserSettingsSelectLiveSpace) private var liveSpaceSelection
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let browser: BrowserStore
    let dataDeleter: any BrowserSpaceDataDeleting

    @State private var selectedSpaceID: UUID?
    @State private var editorSection = BrowserSpaceEditorSection.identity
    @State private var editingAppearanceSpace: SpaceModel?

    var body: some View {
        Group {
            if usesLiveSidebar {
                liveWorkspace
            } else {
                compactSettings
            }
        }
        .crestRepairsSpaceSelection($selectedSpaceID, in: browser)
        .fullScreenCover(item: $editingAppearanceSpace) { requested in
            NavigationStack {
                appearanceWorkspace(for: requested)
                    .navigationTitle("Space identity")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { editingAppearanceSpace = nil }
                        }
                    }
            }
        }
    }

    private var compactSettings: some View {
        BrowserSettingsPane(.spaces) {
            MobileSpaceSelectionSection(
                browser: browser,
                selectedSpaceID: Binding(get: { editedSpaceID }, set: { selectEditedSpace($0) })
            )

            if let space {
                MobileSpaceCustomizationSection(
                    space: space,
                    editAppearance: { editingAppearanceSpace = space }
                )

                detailSections(for: space)
            }
        }
    }

    private var liveWorkspace: some View {
        VStack(spacing: 0) {
            MobileSpaceSettingsWorkspaceToolbar(
                browser: browser,
                selectedSpaceID: Binding(get: { editedSpaceID }, set: { selectEditedSpace($0) }),
                section: $editorSection)
            Divider()
            if let space {

                Group {
                    switch editorSection.kind {
                    case .identity:
                        BrowserSpaceIdentityEditor(
                            name: browser.spaceNameBinding(in: space), color: browser.spaceColorBinding(in: space)
                        )
                    case .settings:
                        Form {
                            detailSections(for: space)
                        }
                    }
                }
                .id(space.id)

            } else {
                ContentUnavailableView("Select a Space", systemImage: "square.grid.2x2")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(BrowserSettingsCanvas.background)
    }

    private func detailSections(for space: SpaceModel) -> some View {
        BrowserSpaceDeletionSection(
            browser: browser,
            spaceID: space.id,
            dataDeleter: dataDeleter)
    }

    private func selectEditedSpace(_ id: UUID?) {
        selectedSpaceID = id
        if usesLiveSidebar, let id, id != browser.shownSpace?.id { liveSpaceSelection?.select(id) }
    }

    @ViewBuilder
    private func appearanceWorkspace(for requested: SpaceModel) -> some View {
        if let currentSpace = browser.spaceModel(requested.id),
            true
        {
            BrowserSpaceIdentityEditor(
                name: browser.spaceNameBinding(in: currentSpace), color: browser.spaceColorBinding(in: currentSpace))
        }
    }

    private var editedSpaceID: UUID? {
        usesLiveSidebar ? browser.selectedSpaceID : selectedSpaceID
    }

    private var space: SpaceModel? {
        guard let editedSpaceID else { return nil }
        return browser.spaceModel(editedSpaceID)
    }

}
