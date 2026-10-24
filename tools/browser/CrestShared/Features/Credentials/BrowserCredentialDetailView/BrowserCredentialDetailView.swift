import SwiftUI

struct BrowserCredentialDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: BrowserCredentialDetailModel

    init(
        browser: BrowserStore,
        spaceAccess: BrowserSpaceAccessController,
        request: BrowserCredentialDetailRequest
    ) {
        _model = State(
            initialValue: BrowserCredentialDetailModel(
                browser: browser,
                spaceAccess: spaceAccess,
                request: request
            )
        )
    }

    init(
        request _: BrowserCredentialDetailRequest,
        model: BrowserCredentialDetailModel
    ) {
        _model = State(initialValue: model)
    }

    var body: some View {
        NavigationStack {
            BrowserCredentialDetailContent(
                model: model,
                dismiss: dismiss.callAsFunction
            )
        }
        .browserCredentialDetailSizing()
        .task(id: model.revealExpiration) {
            guard let expiration = model.revealExpiration else { return }
            await model.expireReveal(at: expiration)
        }
        .task(id: model.copyExpiration) {
            guard let expiration = model.copyExpiration else { return }
            await model.expireCopyConfirmation(at: expiration)
        }
        .onDisappear(perform: model.clearSensitiveState)
    }
}

#Preview("Credential Detail") {
    BrowserCredentialDetailView(
        request: BrowserCredentialDetailPreviewFixture.request,
        model: BrowserCredentialDetailPreviewFixture.makeModel()
    )
}
