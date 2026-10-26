import SwiftUI

/// One saved account the prompt can put into the form.
///
/// The name the credential was saved under carries the row and the login it
/// signs in with sits under it, because the question a list of accounts answers
/// is *which of mine*. The site is not repeated here: every suggestion is an
/// exact-origin match for the one the header already named.
struct BrowserCredentialSuggestionRow: View {
    let suggestion: CredentialDescriptor
    let metrics: BrowserCredentialPromptMetrics
    let fill: () -> Void

    var body: some View {
        Button(action: fill) {
            HStack(spacing: BrowserCredentialPromptMetrics.suggestionRowSpacing) {
                Image(systemName: "person.crop.circle")
                    .font(
                        .system(
                            size: BrowserCredentialPromptMetrics
                                .suggestionRowIconSize
                        )
                    )
                    .foregroundStyle(.secondary)
                VStack(
                    alignment: .leading,
                    spacing: BrowserCredentialPromptMetrics
                        .suggestionRowTextSpacing
                ) {
                    Text(title)
                        .font(.callout)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let detail {
                        Text(detail)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                Spacer(
                    minLength: BrowserCredentialPromptMetrics
                        .suggestionRowSpacerLength
                )
                Image(systemName: "arrow.right.circle.fill")
                    .foregroundStyle(.tint)
            }
            .padding(.horizontal, metrics.suggestionRowHighlightBleed)
            .frame(
                maxWidth: .infinity,
                minHeight: metrics.suggestionRowMinimumHeight,
                alignment: .leading
            )
            .contentShape(.rect)
        }
        .buttonStyle(
            BrowserCredentialSuggestionRowStyle(
                highlightCornerRadius: metrics.suggestionRowHighlightCornerRadius
            )
        )
        .padding(.vertical, metrics.suggestionRowVerticalPadding)
    }

    /// What the row is filed under: the name the credential was saved with,
    /// falling back to the login it signs in with.
    private var title: String {
        guard
            let displayName = suggestion.displayName?.trimmingCharacters(
                in: .whitespacesAndNewlines
            ), !displayName.isEmpty
        else {
            return suggestion.username
        }
        return displayName
    }

    /// The login under the name, where the name is not already it.
    private var detail: String? {
        guard metrics.suggestionRowShowsAccountDetail,
            title != suggestion.username
        else { return nil }
        return suggestion.username
    }
}

/// The row's resting and pressed treatment, where its shell draws one.
///
/// A plain button style everywhere else: a band's rows are aimed at with a
/// finger, which never rests, and a highlight that only ever appears under the
/// thumb already covering it is noise.
private struct BrowserCredentialSuggestionRowStyle: ButtonStyle {
    let highlightCornerRadius: CGFloat?

    @ViewBuilder
    func makeBody(configuration: Configuration) -> some View {
        if let highlightCornerRadius {
            configuration.label
                .crestHoverSurface(
                    cornerRadius: highlightCornerRadius,
                    isPressed: configuration.isPressed
                )
        } else {
            configuration.label
        }
    }
}

#if DEBUG
    #Preview("Pointer and touch") {
        VStack(spacing: 20) {
            BrowserCredentialSuggestionRow(
                suggestion: BrowserCredentialDetailPreviewFixture.descriptor, metrics: .pointer, fill: {})
            BrowserCredentialSuggestionRow(
                suggestion: BrowserCredentialDetailPreviewFixture.descriptor, metrics: .touch, fill: {})
        }.padding().frame(width: 380)
    }
#endif
