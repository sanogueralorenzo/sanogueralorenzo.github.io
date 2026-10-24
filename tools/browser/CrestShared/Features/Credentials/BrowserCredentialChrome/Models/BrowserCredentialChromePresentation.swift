enum BrowserCredentialChromePresentation: Equatable {
    case none
    case save(BrowserCredentialSaveCandidate)
    case strongPassword(BrowserCredentialFillRequest)
    case suggestions(BrowserCredentialFillRequest)

    static func resolve(
        saveCandidate: BrowserCredentialSaveCandidate?,
        fillRequest: BrowserCredentialFillRequest?
    ) -> BrowserCredentialChromePresentation {
        if let saveCandidate {
            return .save(saveCandidate)
        }
        guard let fillRequest else { return .none }
        switch fillRequest.passwordKind {
        case .current:
            return .suggestions(fillRequest)
        case .new:
            return .strongPassword(fillRequest)
        }
    }

    /// The field request behind this prompt, where there is one. A save prompt
    /// answers a form that has already been submitted, so it has no field left
    /// to point at.
    var fillRequest: BrowserCredentialFillRequest? {
        switch self {
        case .none, .save:
            nil
        case .strongPassword(let request), .suggestions(let request):
            request
        }
    }
}
