import SwiftUI

/// What a first run changes on a heraldic Space: the template it starts
/// from, its emblem, its colors and its sidebar.
struct BrowserOnboardingHeraldicSheet: View {
    @Binding var branding: SpaceBranding
    @Binding var symbol: String
    @State private var browsesEmblems = false
    @State private var emblemSearch = ""
    @State private var showsAllEmblems = false
    @State private var choosesEmoji = false

    private var context: BrowserCrestStudioContext {
        BrowserCrestStudioContext(
            branding: $branding, defaults: SpaceHouse.startingPoint(of: branding)?.look ?? branding, compact: false,
            previewBranding: nil)
    }

    private var isIcon: Bool { branding.iconStyle == .simpleSymbol }

    var body: some View {
        VStack(alignment: .leading, spacing: 30) {
            startFrom
            emblem
            colors
            sidebar
            Spacer(minLength: 0)
            Text("Shape, field, band, border and finish: Settings › Spaces.")
                .font(CrestTypography.sans(12, weight: .medium))
                .foregroundStyle(CrestBrandTheme.textDisplay.opacity(0.5))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Sections

    private var startFrom: some View {
        BrowserOnboardingMakeSection("Start from") {
            BrowserOnboardingMakeStrip {
                ForEach(SpaceHouse.all, id: \.self) { house in
                    BrowserOnboardingMakeTile(title: house.title, isSelected: house.isWorn(by: branding)) {
                        branding = house.applying(to: branding)
                    } artwork: {
                        crest(house.applying(to: branding))
                    }
                }
            }
        }
    }

    private var emblem: some View {
        BrowserOnboardingMakeSection("Emblem") {
            Picker("Identity", selection: context.setting(\.iconStyle).binding) {
                Text("Crest").tag(SpaceIconStyle.layeredCrest)
                Text("Icon").tag(SpaceIconStyle.simpleSymbol)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            .fixedSize()
            .accessibilityIdentifier("space-forge-identity")
        } content: {
            if isIcon {
                iconChoices
            } else {
                figureStrip
            }
        }
    }

    /// The first few heraldic figures, the crest's own among them, and a way
    /// to every other.
    private var figureStrip: some View {
        BrowserOnboardingMakeStrip {
            ForEach(offeredFigures, id: \.self) { figure in
                BrowserOnboardingMakeTile(
                    title: figure.title, isSelected: branding.crest.resolvedCharge == .heraldic(figure)
                ) {
                    context.branding.editorUpdate {
                        $0.crest.symbol = figure
                        $0.crest.charge = nil
                        $0.hasCustomAppearance = true
                    }
                } artwork: {
                    crest(
                        context.preview {
                            $0.crest.symbol = figure
                            $0.crest.charge = nil
                        })
                }
            }
            BrowserOnboardingMakeTile(title: "More emblems", isSelected: false) {
                browsesEmblems = true
            } artwork: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(CrestBrandTheme.textDisplay)
            }
            .popover(isPresented: $browsesEmblems, arrowEdge: .bottom) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        BrowserCrestStudioHeraldicEmblemControls(
                            context: context, search: $emblemSearch, showsAll: $showsAllEmblems)
                    }
                    .padding(20)
                }
                .frame(width: 520, height: 480)
                .presentationCompactAdaptation(.popover)
            }
        }
    }

    /// The figures the strip shows: the first of the offered ones, with the
    /// crest's own in place of the last when it is further down.
    private var offeredFigures: [CrestSymbol] {
        var figures = Array(CrestSymbol.selectable.prefix(8))
        if !figures.contains(branding.crest.symbol), figures.count == 8 {
            figures[7] = branding.crest.symbol
        }
        return figures
    }

    private var iconChoices: some View {
        HStack(spacing: 12) {
            BrowserSystemSymbolPicker(
                selection: Binding(
                    get: { BrowserIconSymbol.emoji(from: symbol) == nil ? symbol : "" }, set: { symbol = $0 }))
            BrowserArtworkPickerButton(
                title: "Emoji",
                detail: BrowserIconSymbol.emoji(from: symbol) == nil ? Text("Choose an emoji") : Text("Change emoji")
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
                    setEmoji: { symbol = BrowserIconSymbol.symbol(forEmoji: $0) }))
        }
        .frame(maxWidth: 520)
    }

    private var colors: some View {
        BrowserOnboardingMakeSection("Colors") {
            HStack(spacing: 0) {
                ForEach(BrowserCrestForgeLayer.all) { layer in
                    BrowserOnboardingMakeSwatch(
                        title: layer.title, color: branding.forgeColor(of: layer), isDrawn: layer.isDrawn(by: branding)
                    ) { color in
                        branding.setForgeColor(color, of: layer)
                        branding = branding.normalized()
                    }
                }
                Divider()
                    .frame(height: BrowserOnboardingMakeMetrics.swatchSize)
                    .padding(.horizontal, 10)
                BrowserOnboardingSidebarSwatches(branding: $branding)
            }
        }
    }

    private var sidebar: some View {
        BrowserOnboardingMakeSection("Sidebar") {
            BrowserOnboardingMakeStrip {
                ForEach(SpaceBannerPattern.all, id: \.self) { pattern in
                    BrowserOnboardingMakeTile(
                        title: pattern.title,
                        isSelected: branding.themeMode == .banner && branding.bannerPattern == pattern
                    ) {
                        context.branding.editorUpdate {
                            $0.themeMode = .banner
                            $0.bannerPattern = pattern
                            $0.hasCustomAppearance = true
                        }
                    } artwork: {
                        field(
                            context.preview {
                                $0.themeMode = .banner
                                $0.bannerPattern = pattern
                            })
                    }
                }
                BrowserOnboardingMakeTile(title: "Gradient", isSelected: branding.themeMode == .gradient) {
                    context.branding.editorUpdate {
                        $0.themeMode = .gradient
                        $0.hasCustomAppearance = true
                    }
                } artwork: {
                    field(context.preview { $0.themeMode = .gradient })
                }
            }
        }
    }

    // MARK: - Artwork

    private func crest(_ look: SpaceBranding) -> some View {
        BrowserSpaceCrestIcon(
            branding: look, size: BrowserOnboardingMakeMetrics.tileArtworkSize, rasterizesLayers: false
        )
        .equatable()
    }

    private func field(_ look: SpaceBranding) -> some View {
        BrowserSpaceBannerBackground(branding: look)
            .clipShape(.rect(cornerRadius: 7, style: .continuous))
    }
}

/// The three colors a sidebar wears, each opening the tinctures.
struct BrowserOnboardingSidebarSwatches: View {
    @Binding var branding: SpaceBranding

    var body: some View {
        ForEach(BrowserSpaceBrandColorRole.all) { role in
            BrowserOnboardingMakeSwatch(title: role.title, caption: role.caption, color: branding.forgeColor(of: role))
            {
                color in
                branding.setForgeColor(color, of: role)
                branding = branding.normalized()
            }
        }
    }
}
