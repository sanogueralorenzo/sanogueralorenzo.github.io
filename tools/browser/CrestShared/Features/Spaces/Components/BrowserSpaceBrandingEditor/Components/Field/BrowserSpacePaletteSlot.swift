import SwiftUI

struct BrowserSpacePaletteSlot: View {
    let role: BrowserSpaceBrandColorRole
    let color: Binding<Color>?
    let canAdd: Bool
    let canRemove: Bool
    let compact: Bool
    let addColor: () -> Void
    let removeColor: () -> Void

    private var usesTouch: Bool {
        #if os(iOS)
            true
        #else
            false
        #endif
    }

    var body: some View {
        VStack(spacing: 8) {
            Group {
                if let color {
                    PlatformSpacePaletteColorWell(selection: color)
                        .accessibilityLabel(Text(role.title))
                        .accessibilityIdentifier(
                            "space-branding-\(role.name)-color-picker")
                } else {
                    Button(action: addColor) {
                        Image(systemName: "plus")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(.primary.opacity(0.035), in: .rect(cornerRadius: 12))
                            .overlay {
                                RoundedRectangle(cornerRadius: 12)
                                    .strokeBorder(
                                        .secondary.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [4]))
                            }
                            .contentShape(.rect(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .disabled(!canAdd)
                    .opacity(canAdd ? 1 : CrestOpacity.disabled)
                    .accessibilityLabel(Text(role.addTitle))
                    .accessibilityIdentifier("space-branding-add-\(role.name)-color")
                }
            }
            .frame(height: compact ? 56 : 64)
            .clipShape(.rect(cornerRadius: 12))
            .overlay(alignment: .topTrailing) {
                if canRemove {
                    Button(action: removeColor) {
                        Image(systemName: "minus")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 22, height: 22)
                            .background(Color.red, in: .circle)
                            .overlay {
                                Circle().strokeBorder(.white.opacity(0.65), lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                    .frame(width: usesTouch ? 44 : 22, height: usesTouch ? 44 : 22)
                    .contentShape(.rect)
                    .offset(x: usesTouch ? 11 : 5, y: usesTouch ? -11 : -5)
                    .accessibilityLabel(Text(role.removeTitle))
                    .accessibilityIdentifier("space-branding-remove-\(role.name)-color")
                }
            }
            Text(role.title)
                .font(CrestTypography.metadata)
                .lineLimit(1)
                .minimumScaleFactor(BrowserSpaceForgeMetrics.paletteLabelMinimumScale)
        }
        .frame(maxWidth: .infinity)
    }
}
