import SwiftUI

struct BrowserInstalledImportSourceGrid: View {
    let sources: [BrowserInstalledImportSource]
    let isSelected: (BrowserInstalledImportSource) -> Bool
    let accessLabel: (BrowserInstalledImportSource) -> String?
    let toggleSelection: (BrowserInstalledImportSource) -> Void

    private var rows: [[BrowserInstalledImportSource]] {
        stride(from: 0, to: sources.count, by: 3).map { start in
            Array(sources[start..<min(start + 3, sources.count)])
        }
    }

    var body: some View {
        VStack(spacing: 20) {
            ForEach(rows, id: \.first?.id) { row in
                HStack(alignment: .top, spacing: 20) {
                    ForEach(row) { source in
                        BrowserInstalledImportSourceCard(
                            source: source,
                            isSelected: isSelected(source),
                            accessLabel: accessLabel(source),
                            toggleSelection: {
                                toggleSelection(source)
                            }
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }
}

/// One browser as a tile: its icon and name, and what reading it takes once
/// setup knows.
private struct BrowserInstalledImportSourceCard: View {
    let source: BrowserInstalledImportSource
    let isSelected: Bool
    let accessLabel: String?
    let toggleSelection: () -> Void

    var body: some View {
        Button(action: toggleSelection) {
            VStack(spacing: 12) {
                Image(nsImage: source.icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 60, height: 60)
                    .accessibilityHidden(true)
                Text(source.title)
                    .font(CrestTypography.sans(15, weight: .semibold))
                    .foregroundStyle(CrestBrandTheme.textDisplay)
                    .lineLimit(1)
                Text(accessLabel ?? "")
                    .font(CrestTypography.sans(11, weight: .medium))
                    .foregroundStyle(CrestBrandTheme.textDisplay.opacity(0.6))
                    .lineLimit(1)
                    .frame(height: 14)
            }
            .frame(width: 196, height: 176)
            .contentShape(.rect(cornerRadius: CrestRadius.card, style: .continuous))
            .background {
                RoundedRectangle(cornerRadius: CrestRadius.card, style: .continuous)
                    .fill(CrestBrandTheme.canvas.opacity(isSelected ? 0.12 : 0.07))
            }
            .overlay {
                RoundedRectangle(cornerRadius: CrestRadius.card, style: .continuous)
                    .strokeBorder(
                        isSelected ? CrestBrandTheme.accent : CrestBrandTheme.line,
                        lineWidth: isSelected ? 3 : CrestLayout.hairline
                    )
            }
            .overlay(alignment: .topTrailing) {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(CrestBrandTheme.canvas)
                        .frame(width: 22, height: 22)
                        .background(CrestBrandTheme.accent, in: .circle)
                        .padding(10)
                        .accessibilityHidden(true)
                }
            }
        }
        .buttonStyle(.plain)

        .accessibilityLabel("Import from \(source.title)")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint(accessibilityHint)
    }

    /// What going on with this browser does: an unscanned browser's data is
    /// read then and may need access, found data is reviewed, and otherwise
    /// Crest asks for the folder.
    private var accessibilityHint: Text {
        guard source.detectedPayload != nil else {
            return Text("Crest reads its data when you continue, which may ask for access")
        }
        return source.hasDetectedData
            ? Text("Review its Spaces and tabs")
            : Text("Crest locates the browser data folder and asks for one-time read access")
    }
}
