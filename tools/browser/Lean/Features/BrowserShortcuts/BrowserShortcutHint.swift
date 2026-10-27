import SwiftUI

/// The fork's inline hint, with a native chord string instead of a generated binding record.
struct BrowserShortcutHint: View {
    let text: String
    @ScaledMetric(relativeTo: .caption) private var fontSize = 12

    var body: some View {
        Text(verbatim: text)
            .font(.system(size: fontSize, weight: .medium, design: .monospaced))
            .foregroundStyle(.secondary)
            .fixedSize()
            .padding(.horizontal, LeanSpacing.extraSmall)
            .accessibilityHidden(true)
    }
}
