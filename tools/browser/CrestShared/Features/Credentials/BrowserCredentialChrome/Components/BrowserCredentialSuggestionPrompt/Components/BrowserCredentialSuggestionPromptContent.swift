import SwiftUI

struct BrowserCredentialSuggestionPromptContent: View {
    let request: BrowserCredentialFillRequest
    let space: BrowserSpaceIdentity?
    let siteIconData: Data?
    let model: BrowserCredentialSuggestionModel
    let fillErrorMessage: String?
    let metrics: BrowserCredentialPromptMetrics
    let dismiss: () -> Void
    let fill: (CredentialDescriptor) -> Void

    var body: some View {
        VStack(
            alignment: .leading,
            spacing: BrowserCredentialPromptMetrics.contentSpacing
        ) {
            BrowserCredentialPromptHeader(
                kind: .suggestions,
                request: request,
                space: space,
                siteIconData: siteIconData,
                metrics: metrics,
                dismiss: dismiss
            )
            if request.isCrossOriginFrame {
                BrowserCredentialCrossOriginNotice(
                    message: "Embedded sign-in from \(request.topLevelOrigin.description)"
                )
            }
            BrowserCredentialSuggestionState(
                isLoading: model.isLoading,
                suggestions: model.suggestions,
                metrics: metrics,
                fill: fill
            )
            if model.hasFailed {
                BrowserCredentialPromptError(
                    "Crest couldn’t read this Space’s passwords."
                )
            }
            if let fillErrorMessage {
                BrowserCredentialPromptError(verbatim: fillErrorMessage)
            }
        }
    }
}
