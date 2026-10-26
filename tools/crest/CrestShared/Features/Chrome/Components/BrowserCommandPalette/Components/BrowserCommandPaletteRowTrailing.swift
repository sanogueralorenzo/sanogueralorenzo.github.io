import SwiftUI

/// What a row says at its end: where Return opens it while the person holds
/// modifier keys, else its command's shortcut, its kind in the blended
/// layout, or what activating it does.
struct BrowserCommandPaletteRowTrailing: View {
    let model: BrowserCommandPaletteModel
    let row: PaletteRow
    var isSelected = false
    var namesKind = false

    @ViewBuilder
    var body: some View {
        Group {
            if isSelected, let title = model.selectedOpening.title {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .transition(.blurReplace)
            } else if let command = row.command,
                let chord = model.commands?.shortcut(for: command)
            {
                Text(verbatim: chord.displayString)
                    .font(.caption.weight(.medium).monospaced())
                    .foregroundStyle(.secondary)
                    .padding(
                        .horizontal,
                        BrowserCommandPaletteMetrics.shortcutHorizontalPadding
                    )
                    .frame(minHeight: BrowserCommandPaletteMetrics.shortcutMinimumHeight)
                    .background(
                        .primary.opacity(
                            BrowserCommandPaletteMetrics.shortcutBackgroundOpacity
                        ),
                        in: .rect(
                            cornerRadius: BrowserCommandPaletteMetrics.shortcutCornerRadius
                        )
                    )
                    .accessibilityLabel(Text(verbatim: chord.spokenDescription))
            } else if namesKind {
                Text(row.kind.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let action = row.kind.action {
                Text(action)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .animation(.snappy(duration: CrestMotion.hoverTransition), value: model.selectedOpening)
    }
}

#if DEBUG
    #Preview("Command shortcut") {
        BrowserCommandPaletteRowTrailing(
            model: BrowserCommandPalettePreviewFixture.model(query: "swift"),
            row: BrowserCommandPalettePreviewFixture.commandRow
        ).padding()
    }
#endif
