import Foundation

enum BrowserDataPortabilityOperationMessage {
    case localized(LocalizedStringResource)
    case verbatim(String)
}

struct BrowserDataPortabilityOperationStatus {
    let message: BrowserDataPortabilityOperationMessage
    let isError: Bool

    init(_ message: LocalizedStringResource) {
        self.message = .localized(message)
        isError = false
    }

    init(error: Error) {
        message = .verbatim(error.personFacingDescription)
        isError = true
    }

    var symbol: String {
        isError ? "exclamationmark.triangle.fill" : "checkmark.circle"
    }
}
