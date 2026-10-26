import SwiftUI

/// What the prompt shows while the Space's vault is answering, and what it shows
/// when the answer is nothing.
struct BrowserCredentialSuggestionState: View {
    let isLoading: Bool
    let suggestions: [CredentialDescriptor]
    let metrics: BrowserCredentialPromptMetrics
    let fill: (CredentialDescriptor) -> Void

    @ViewBuilder
    var body: some View {
        if isLoading {
            ProgressView("Checking this Space…")
                .controlSize(.small)
                .frame(minHeight: metrics.suggestionStateMinimumHeight)
        } else if suggestions.isEmpty {
            empty
        } else {
            BrowserCredentialSuggestionList(
                suggestions: suggestions,
                metrics: metrics,
                fill: fill
            )
        }
    }

    /// A panel with nothing to offer says so and stops; a band says the whole
    /// sentence, because it has already taken the room to say it in.
    @ViewBuilder
    private var empty: some View {
        switch metrics.suggestionEmptyStatePresentation {
        case .compact:
            Label {
                Text("No passwords saved for this site")
            } icon: {
                Image(systemName: "key.slash")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .labelStyle(
                BrowserCredentialCompactLabelStyle(
                    spacing: BrowserCredentialPromptMetrics
                        .suggestionEmptySpacing,
                    symbolSize: BrowserCredentialPromptMetrics
                        .suggestionEmptySymbolSize
                )
            )
        case .sentence:
            Text("No Crest passwords are saved for this site in this Space.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(
                    minHeight: metrics.suggestionStateMinimumHeight,
                    alignment: .leading
                )
        }
    }
}

/// A glyph and a remark on one line, the glyph sized to the remark rather than
/// to the row a `Label` would otherwise reserve for it.
private struct BrowserCredentialCompactLabelStyle: LabelStyle {
    let spacing: CGFloat
    let symbolSize: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: spacing) {
            configuration.icon
                .font(.system(size: symbolSize))
            configuration.title
        }
    }
}

#if DEBUG
    #Preview("Loading, empty, and available") {
        VStack(spacing: 20) {
            BrowserCredentialSuggestionState(isLoading: true, suggestions: [], metrics: .pointer, fill: { _ in })
            BrowserCredentialSuggestionState(isLoading: false, suggestions: [], metrics: .pointer, fill: { _ in })
            BrowserCredentialSuggestionState(
                isLoading: false, suggestions: [BrowserCredentialDetailPreviewFixture.descriptor], metrics: .pointer,
                fill: { _ in })
        }.padding().frame(width: 380)
    }
#endif
