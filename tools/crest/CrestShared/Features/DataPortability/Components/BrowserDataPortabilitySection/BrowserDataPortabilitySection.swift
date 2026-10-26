import SwiftUI

struct BrowserDataPortabilitySection: View {
    @State private var model: BrowserDataPortabilityModel

    let showsMacOSImportRequirement: Bool
    private let presentsSystemPanels: Bool

    init(
        browser: BrowserStore,
        spaceAccess: BrowserSpaceAccessController,
        showsMacOSImportRequirement: Bool = false
    ) {
        _model = State(
            initialValue: BrowserDataPortabilityModel(
                browser: browser,
                spaceAccess: spaceAccess
            )
        )
        self.showsMacOSImportRequirement = showsMacOSImportRequirement
        presentsSystemPanels = true
    }

    init(
        model: BrowserDataPortabilityModel,
        showsMacOSImportRequirement: Bool = false,
        presentsSystemPanels: Bool = false
    ) {
        _model = State(initialValue: model)
        self.showsMacOSImportRequirement = showsMacOSImportRequirement
        self.presentsSystemPanels = presentsSystemPanels
    }

    var body: some View {
        BrowserDataPortabilityDocumentPresenter(
            model: model,
            presentsSystemPanels: presentsSystemPanels
        ) {
            BrowserDataPortabilityContent(
                model: model,
                showsMacOSImportRequirement: showsMacOSImportRequirement
            )
        }
        .onChange(of: model.lockedSpaceIDs) { _, spaceIDs in
            if !spaceIDs.isEmpty {
                model.cancelSensitiveExports()
            }
        }
    }
}
