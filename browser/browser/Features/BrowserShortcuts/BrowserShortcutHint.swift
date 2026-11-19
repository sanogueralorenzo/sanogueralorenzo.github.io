import SwiftUI

/// Adapted from Crest's inline shortcut hint.
struct BrowserShortcutHint: View {
    let text: String
    @ScaledMetric(relativeTo: .caption) private var fontSize = 12

    var body: some View {
        Text(verbatim: text)
            .font(.system(size: fontSize, weight: .medium, design: .monospaced))
            .foregroundStyle(.secondary)
            .fixedSize()
            .padding(.horizontal, BrowserSpacing.extraSmall)
            .accessibilityHidden(true)
    }
}
