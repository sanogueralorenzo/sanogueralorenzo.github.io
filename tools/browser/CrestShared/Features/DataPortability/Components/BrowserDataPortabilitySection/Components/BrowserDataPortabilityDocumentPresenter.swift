import SwiftUI
import UniformTypeIdentifiers

struct BrowserDataPortabilityDocumentPresenter<Content: View>: View {
    @Bindable var model: BrowserDataPortabilityModel
    let presentsSystemPanels: Bool
    let content: Content

    init(
        model: BrowserDataPortabilityModel,
        presentsSystemPanels: Bool,
        @ViewBuilder content: () -> Content
    ) {
        self.model = model
        self.presentsSystemPanels = presentsSystemPanels
        self.content = content()
    }

    var body: some View {
        if presentsSystemPanels {
            content
                .fileExporter(
                    isPresented: $model.isExporting,
                    document: model.exportDocument,
                    contentType: model.exportDocument?.format.uniformType ?? .data,
                    defaultFilename: model.exportDocument?.format.fileName,
                    onCompletion: model.finishExport
                )
                .fileImporter(
                    isPresented: $model.isImporting,
                    allowedContentTypes: [.json],
                    allowsMultipleSelection: false,
                    onCompletion: model.finishImport
                )
        } else {
            content
        }
    }
}
