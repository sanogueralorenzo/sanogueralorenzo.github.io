import SwiftUI

/// The saved accounts the prompt offers.
///
/// A pointer shell lets the list grow its panel; a touch shell keeps it inside a
/// band it scrolls, because the prompt is pushing the page down while it is up.
struct BrowserCredentialSuggestionList: View {
    let suggestions: [CredentialDescriptor]
    let metrics: BrowserCredentialPromptMetrics
    let fill: (CredentialDescriptor) -> Void

    @ViewBuilder
    var body: some View {
        if let maximumHeight = metrics.suggestionListMaximumHeight {
            ScrollView {
                LazyVStack(spacing: 0) { rows }
            }
            .frame(maxHeight: maximumHeight)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                rows
            }
            // The rows pad themselves out so their highlight reaches past the
            // text; the list pulls that back so the text still lines up with
            // everything above it.
            .padding(.horizontal, -metrics.suggestionRowHighlightBleed)
        }
    }

    private var rows: some View {
        ForEach(suggestions) { suggestion in
            BrowserCredentialSuggestionRow(
                suggestion: suggestion,
                metrics: metrics,
                fill: { fill(suggestion) }
            )
        }
    }
}
