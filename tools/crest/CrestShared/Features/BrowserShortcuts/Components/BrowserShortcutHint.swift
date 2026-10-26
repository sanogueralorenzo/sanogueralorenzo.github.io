import SwiftUI

/// An informational keyboard equivalent inside an action's label.
struct BrowserShortcutHint: View {
    let shortcut: BrowserShortcut?

    @Environment(\.browserShowsInlineShortcuts) private var isVisible
    @Environment(\.locale) private var locale
    @ScaledMetric(relativeTo: .caption) private var fontSize = 12

    var body: some View {
        if isVisible, let shortcut {
            Text(verbatim: shortcut.displayString(locale: locale))
                .font(.system(size: fontSize, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .fixedSize()
                .padding(.horizontal, CrestSpacing.extraSmall)
                .accessibilityHidden(true)
        }
    }
}

extension EnvironmentValues {
    @Entry var browserShortcutBindings: [ShortcutCommand: ShortcutBinding]?
    @Entry var browserShowsInlineShortcuts = true
}
