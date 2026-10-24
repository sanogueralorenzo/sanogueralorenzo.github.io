import SwiftUI

/// What a first run changes on a modern Space: its colors, whether they run
/// as a gradient or stand solid, and its icon.
struct BrowserOnboardingModernSheet: View {
    @Binding var branding: SpaceBranding
    @Binding var symbol: String
    @State private var choosesEmoji = false

    /// The color sets a modern Space may wear: the accents' own, each
    /// scheme's, then each template's sidebar colors.
    private var presets: [[BrandColor]] {
        SpaceAccent.all.map(\.legacyColors) + SpaceScheme.all.map { Array($0.look.colors) }
            + SpaceHouse.all.map { Array($0.look.colors) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 30) {
            colors
            fill
            icon
            Spacer(minLength: 0)
            Text("Patterns and crests: Settings › Spaces.")
                .font(CrestTypography.sans(12, weight: .medium))
                .foregroundStyle(CrestBrandTheme.textDisplay.opacity(0.5))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Sections

    private var colors: some View {
        BrowserOnboardingMakeSection("Color") {
            VStack(alignment: .leading, spacing: 16) {
                BrowserOnboardingMakeStrip {
                    ForEach(Array(presets.enumerated()), id: \.offset) { _, preset in
                        BrowserOnboardingModernPresetSwatch(
                            colors: preset, isSelected: Array(branding.colors) == preset
                        ) {
                            $branding.editorUpdate {
                                $0.colors = ColorPalette(colors: preset)
                                $0.hasCustomAppearance = true
                            }
                        }
                    }
                }
                BrowserOnboardingMakeStrip(spacing: 0) {
                    BrowserOnboardingSidebarSwatches(branding: $branding)
                }
            }
        }
    }

    private var fill: some View {
        BrowserOnboardingMakeSection("Fill") {
            Picker("Fill", selection: isGradient) {
                Text("Gradient").tag(true)
                Text("Solid").tag(false)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            .fixedSize()
        }
    }

    private var icon: some View {
        BrowserOnboardingMakeSection("Icon") {
            HStack(spacing: 12) {
                BrowserSystemSymbolPicker(
                    selection: Binding(
                        get: { BrowserIconSymbol.emoji(from: symbol) == nil ? symbol : "" },
                        set: { wearIcon($0) }))
                BrowserArtworkPickerButton(
                    title: "Emoji",
                    detail: BrowserIconSymbol.emoji(from: symbol) == nil
                        ? Text("Choose an emoji") : Text("Change emoji")
                ) {
                    choosesEmoji = true
                } artwork: {
                    if let emoji = BrowserIconSymbol.emoji(from: symbol) {
                        Text(emoji)
                    } else {
                        Image(systemName: "face.smiling")
                    }
                }
                .accessibilityLabel("Choose Emoji")
                .browserIconCustomizationPopover(
                    .init(
                        isPresented: $choosesEmoji, title: "Space Icon",
                        currentEmoji: BrowserIconSymbol.emoji(from: symbol),
                        setEmoji: { wearIcon(BrowserIconSymbol.symbol(forEmoji: $0)) }))
            }
            .frame(maxWidth: 520)
        }
    }

    /// Gives the Space `symbol` as a plain icon, which a Space that came with
    /// a crest then shows in its place.
    private func wearIcon(_ symbol: String) {
        self.symbol = symbol
        if branding.iconStyle != .simpleSymbol {
            $branding.editorUpdate {
                $0.iconStyle = .simpleSymbol
                $0.hasCustomAppearance = true
            }
        }
    }

    // MARK: - Choices

    /// Whether the sidebar runs its colors as a gradient; otherwise it stands
    /// solid in its background color.
    private var isGradient: Binding<Bool> {
        Binding(
            get: { branding.themeMode == .gradient },
            set: { gradient in
                $branding.editorUpdate {
                    $0.themeMode = gradient ? .gradient : .banner
                    if !gradient { $0.bannerPattern = .solid }
                    $0.hasCustomAppearance = true
                }
            })
    }
}

/// A set of colors as one round swatch, running from the first to the last.
private struct BrowserOnboardingModernPresetSwatch: View {
    let colors: [BrandColor]
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            Circle()
                .fill(
                    LinearGradient(
                        colors: colors.map(\.color), startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .frame(width: 44, height: 44)
                .overlay { Circle().strokeBorder(CrestBrandPalette.paper.opacity(0.2), lineWidth: 1) }
                .padding(4)
                .overlay { Circle().strokeBorder(isSelected ? CrestBrandPalette.butter : .clear, lineWidth: 3) }
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(colors.map { String(localized: $0.title) }.joined(separator: ", ")))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
