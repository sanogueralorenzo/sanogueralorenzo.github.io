import SwiftUI

/// What a transient overlay puts on screen when the Space behind it goes away.
///
/// The overlay cannot outlive its Space either way; what differs is whether
/// there is anything left to say so against.
enum BrowserTransientUnavailableSpacePresentation {
    /// Explain the loss and wait to be closed. The overlay stands inside a
    /// window the person is still looking at, so vanishing without a word
    /// would leave them wondering what became of it.
    case explanation(BrowserTransientUnavailableSpaceVocabulary)

    /// Close at once. The overlay is the whole screen, and what it would
    /// explain itself against is the thing that just disappeared.
    case immediateDismissal
}

/// The words an explained loss uses.
struct BrowserTransientUnavailableSpaceVocabulary {
    let title: LocalizedStringKey
    let systemImage: String
    let description: LocalizedStringKey
    let dismissTitle: LocalizedStringKey
}

/// Stands in for a transient overlay whose Space is gone.
struct BrowserTransientUnavailableSpaceView: View {
    let requestID: UUID
    let presentation: BrowserTransientUnavailableSpacePresentation
    let dismiss: () -> Void

    var body: some View {
        switch presentation {
        case .explanation(let vocabulary):
            explanation(vocabulary)
        case .immediateDismissal:
            Color.clear
                .task(id: requestID) {
                    dismiss()
                }
                .accessibilityHidden(true)
        }
    }

    private func explanation(
        _ vocabulary: BrowserTransientUnavailableSpaceVocabulary
    ) -> some View {
        ContentUnavailableView {
            Label(vocabulary.title, systemImage: vocabulary.systemImage)
        } description: {
            Text(vocabulary.description)
        } actions: {
            Button(vocabulary.dismissTitle, action: dismiss)
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }
}
