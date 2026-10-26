import SwiftUI

/// The row a touch shell gives the save prompt's actions, held to the trailing
/// edge and stacked once the text is large enough that the two would not fit
/// beside each other.
struct BrowserCredentialSaveActionRow: View {
    let route: BrowserCredentialPromptRoute
    let space: BrowserSpaceIdentity?
    let metrics: BrowserCredentialPromptMetrics
    let dismiss: () -> Void
    let perform: (BrowserCredentialPromptPrimaryAction) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @ViewBuilder
    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            actions(isStacked: true)
                .frame(maxWidth: .infinity, alignment: .trailing)
        } else {
            HStack {
                Spacer(minLength: 0)
                actions(isStacked: false)
            }
        }
    }

    private func actions(isStacked: Bool) -> BrowserCredentialSaveActions {
        BrowserCredentialSaveActions(
            route: route,
            space: space,
            metrics: metrics,
            isStacked: isStacked,
            dismiss: dismiss,
            perform: perform
        )
    }
}
