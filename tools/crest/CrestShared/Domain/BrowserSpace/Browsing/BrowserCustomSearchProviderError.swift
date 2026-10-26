import Foundation

/// The core's refusal of a custom engine, with the explanation the editor
/// shows. A flaw explains itself, as does a duplicate name or the Space's
/// limit; any other refusal reads as an invalid template.
struct BrowserCustomSearchProviderError: LocalizedError, Equatable {
    let errorDescription: String?

    init(_ rejection: Rejection) {
        errorDescription =
            switch rejection {
            case .invalidSearchEngine(let invalid): String(localized: invalid.flaw.message)
            default: String(localized: rejection.message ?? SearchEngineFlaw.invalidTemplate.message)
            }
    }
}
