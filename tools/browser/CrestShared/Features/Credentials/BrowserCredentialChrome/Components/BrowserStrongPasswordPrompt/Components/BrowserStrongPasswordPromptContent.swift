import SwiftUI

struct BrowserStrongPasswordPromptContent: View {
    let request: BrowserCredentialFillRequest
    let space: BrowserSpaceIdentity?
    let siteIconData: Data?
    let model: BrowserStrongPasswordOperationModel
    let metrics: BrowserCredentialPromptMetrics
    let dismiss: () -> Void
    let generateAndFill: () -> Void

    var body: some View {
        VStack(
            alignment: .leading,
            spacing: BrowserCredentialPromptMetrics.strongPasswordContentSpacing
        ) {
            BrowserCredentialPromptHeader(
                kind: .strongPassword,
                request: request,
                space: space,
                siteIconData: siteIconData,
                metrics: metrics,
                dismiss: dismiss
            )
            if request.isCrossOriginFrame {
                BrowserCredentialCrossOriginNotice(
                    message: "Embedded password form from \(request.topLevelOrigin.description)"
                )
            }
            BrowserStrongPasswordExplanation(
                spaceName: space?.name ?? "this Space"
            )
            BrowserStrongPasswordActionButton(
                isWorking: model.isWorking,
                tint: space?.accent.tint.color ?? .accentColor,
                metrics: metrics,
                action: generateAndFill
            )
            if model.phase == .failedBeforeSave {
                BrowserCredentialPromptError(
                    "Crest couldn’t save a strong password. Nothing was filled."
                )
            } else if model.phase == .savedButFillFailed {
                BrowserCredentialPromptError(
                    "The password is saved in this Space, but the form changed before Crest could fill it."
                )
            }
        }
    }
}
