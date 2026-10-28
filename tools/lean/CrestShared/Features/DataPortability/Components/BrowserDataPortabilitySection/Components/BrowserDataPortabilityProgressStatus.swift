import SwiftUI

struct BrowserDataPortabilityProgressStatus: View {
    let model: BrowserDataPortabilityModel

    var body: some View {
        if let format = model.preparingFormat {
            ProgressView(format.preparingMessage)
        }

        if let status = model.status {
            Label {
                switch status.message {
                case .localized(let message):
                    Text(message)
                case .verbatim(let message):
                    Text(message)
                }
            } icon: {
                Image(systemName: status.symbol)
            }
            .foregroundStyle(status.isError ? .red : .secondary)
            .font(.footnote)
            .accessibilityIdentifier("browser-data-operation-status")
        }
    }
}
