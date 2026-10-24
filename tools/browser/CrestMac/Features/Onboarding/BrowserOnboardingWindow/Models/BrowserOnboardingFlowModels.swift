import Foundation

struct BrowserOnboardingPreparedImport {
    let passwords: [BrowserImportedPassword]
}

enum BrowserOnboardingFailureText: Equatable {
    case localized(LocalizedStringResource)
    case verbatim(String)
}

extension SetupFailure {
    /// What the person is told of the failure: the words the Mac gave it, or
    /// Crest's own for a browser that went or a folder without its data.
    var message: BrowserOnboardingFailureText {
        if let detail { return .verbatim(detail) }
        guard reason == .dataFolder, let source else {
            return .localized(
                LocalizedStringResource(
                    "That browser is no longer available on this Mac.",
                    comment: "Browser-import error shown when a selected source app disappears."))
        }
        return .localized(
            LocalizedStringResource(
                "Crest could not read \(source.title) data there. Try Allow Access again, or choose the \(source.title) data folder if it moved.",
                comment: "Browser-import error. Both variables are the source browser name."))
    }
}
