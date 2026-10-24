import SwiftUI

/// Shared sizing and presentation for the symbol and emoji library buttons.
struct BrowserArtworkPickerButton<Artwork: View>: View {
    let title: LocalizedStringKey
    let detail: Text
    let action: () -> Void
    @ViewBuilder var artwork: () -> Artwork

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                artwork()
                    .font(.title2)
                    .foregroundStyle(.tint)
                    .frame(width: 36, height: 36)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.body.weight(.medium))
                    detail.font(.caption).foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 40)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect(cornerRadius: 12))
        }
        .buttonStyle(ArtworkPickerStyle())
    }
}

private struct ArtworkPickerStyle: ButtonStyle {
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.primary)
            .background(
                .primary.opacity(configuration.isPressed ? 0.10 : isHovered ? 0.07 : 0.035),
                in: .rect(cornerRadius: 12)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(.primary.opacity(contrast == .increased ? 0.4 : isHovered ? 0.18 : 0.09))
                    .allowsHitTesting(false)
            }
            .opacity(isEnabled ? 1 : 0.5)
            .onHover { isHovered = $0 }
    }
}
