import SwiftUI

struct BrowserCrestStudioColors: View {
    let context: BrowserCrestStudioContext
    let symbol: String
    @State private var rememberedPalette: ColorPalette?

    private var colors: ColorPalette { context.value.crest.layerColors(spaceColors: context.value.colors) }
    private var followsSpace: Binding<Bool> {
        Binding(
            get: { !context.value.crest.usesOwnPalette },
            set: { follows in
                if follows { rememberedPalette = context.value.crest.palette }
                context.crest(\.palette).binding.wrappedValue =
                    follows ? nil : (rememberedPalette ?? context.value.colors)
            })
    }

    var body: some View {
        BrowserCrestStudioGroup(
            title: "Crest colors", systemImage: "paintpalette", preview: context.compact ? context.value : nil,
            symbol: symbol
        ) {
            let palette = context.crest(\.palette)
            CrestSettingRow("Follow Space colors", setting: palette.resettable("Crest colors")) {
                Toggle("Follow Space colors", isOn: followsSpace).labelsHidden()
            }
            paletteWells
            if context.value.crest.usesOwnPalette {
                Text("Up to four colors, independent of the sidebar background.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var paletteWells: some View {
        HStack(spacing: 16) {
            ForEach(colors.indices, id: \.self) { index in
                VStack(spacing: 8) {
                    ColorPicker(
                        "Color \(index + 1)",
                        selection: Binding(
                            get: { colors[index].color },
                            set: { color in
                                var updated = colors
                                updated[index] = BrandColor(color: color)
                                updatePalette(updated)
                            }), supportsOpacity: false
                    ).labelsHidden()
                    Text("\(index + 1)").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            if colors.count > 1 {
                Button("Remove last color", systemImage: "minus") {
                    updatePalette(ColorPalette(colors.dropLast()))
                }.labelStyle(.iconOnly).buttonStyle(.borderless)
            }
            if colors.count < maximumColorCount {
                Button("Add color", systemImage: "plus") {
                    updatePalette(colors + [.sand])
                }.labelStyle(.iconOnly).buttonStyle(.borderless)
            }
        }
    }

    private var maximumColorCount: Int {
        context.value.crest.usesOwnPalette
            ? SpaceCrest.maximumPaletteCount : SpaceBranding.maximumColorCount
    }

    private func updatePalette(_ colors: ColorPalette) {
        if context.value.crest.usesOwnPalette {
            context.crest(\.palette).binding.wrappedValue = colors
        } else {
            context.setting(\.colors).binding.wrappedValue = colors
        }
    }
}

struct BrowserCrestStudioColorRow: View {
    let context: BrowserCrestStudioContext
    let title: LocalizedStringKey
    let path: WritableKeyPath<SpaceCrest, Int>

    var body: some View {
        let colors = context.value.crest.layerColors(spaceColors: context.value.colors)
        let setting = context.crest(path)
        return CrestSettingRow(title, setting: setting.resettable(title)) {
            HStack(spacing: 8) {
                ForEach(colors.indices, id: \.self) { index in
                    Button {
                        setting.binding.wrappedValue = index
                    } label: {
                        Circle().fill(colors[index].color)
                            .frame(width: 22, height: 22)
                            .overlay { Circle().strokeBorder(.primary.opacity(0.2)) }
                            .padding(4)
                            .overlay {
                                Circle().strokeBorder(
                                    setting.wrappedValue == index ? CrestBrandTheme.accent : .clear, lineWidth: 2)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("\(Text(title)), color \(index + 1)"))
                    .accessibilityAddTraits(setting.wrappedValue == index ? .isSelected : [])
                }
            }
        }
    }
}

struct BrowserCrestStudioBackground: View {
    let context: BrowserCrestStudioContext
    let symbol: String
    var body: some View {
        BrowserCrestStudioGroup(title: "Space background", systemImage: "rectangle.inset.filled") {
            if context.compact {
                BrowserCrestStudioPreview(branding: context.value, symbol: symbol, compact: true)
            }
            HStack(spacing: 16) {
                ForEach(BrowserSpaceBrandColorRole.all) { role in
                    BrowserSpacePaletteSlot(
                        role: role, color: context.branding.editorColor(for: role),
                        canAdd: role.slot == context.value.colors.count,
                        canRemove: role.slot == context.value.colors.count - 1 && context.value.colors.count > 1,
                        compact: true, addColor: { context.branding.editorAddColor(for: role) },
                        removeColor: { context.branding.editorRemoveColor(for: role) })
                }
            }
            backgroundChoices
            if context.value.themeMode == .gradient {
                let angle = context.setting(\.gradientAngle)
                CrestSettingRow("Gradient angle", setting: angle.resettable("Gradient angle")) {
                    HStack(spacing: 16) {
                        Text("\(Int(angle.wrappedValue.rounded()))°")
                            .monospacedDigit().foregroundStyle(.secondary)
                        BrowserSpaceGradientAngleDial(angle: angle.binding, color: context.value.secondaryColor.color)
                            .frame(width: 72, height: 72)
                    }
                }
            }
            slider("Color intensity", \.bannerStrength)
            slider("Readability fade", \.readabilityFade)
            slider("Folder color intensity", \.folderColorIntensity)
            let texture = context.setting(\.showsTexture)
            CrestSettingRow("Texture", setting: texture.resettable("Texture")) {
                Toggle("Texture", isOn: texture.binding).labelsHidden()
            }
            let text = context.setting(\.textColorMode)
            CrestSettingRow("Text color", setting: text.resettable("Text color")) {
                Picker("Text color", selection: text.binding) {
                    ForEach(SpaceTextColorMode.all, id: \.self) { Text($0.title).tag($0) }
                }.labelsHidden()
            }
        }
    }

    private var backgroundChoices: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 10)], spacing: 10) {
            ForEach(SpaceBannerPattern.all, id: \.self) { pattern in
                BrowserCrestStudioChoice(
                    title: pattern.title,
                    selected: context.value.themeMode == .banner && context.value.bannerPattern == pattern
                ) {
                    context.branding.editorUpdate {
                        $0.themeMode = .banner
                        $0.bannerPattern = pattern
                        $0.hasCustomAppearance = true
                    }
                } artwork: {
                    BrowserSpaceBannerBackground(
                        branding: context.preview {
                            $0.themeMode = .banner
                            $0.bannerPattern = pattern
                        }
                    )
                    .frame(width: 56, height: 48).clipShape(.rect(cornerRadius: 8))
                }
            }
            BrowserCrestStudioChoice(title: "Gradient", selected: context.value.themeMode == .gradient) {
                context.setting(\.themeMode).binding.wrappedValue = .gradient
            } artwork: {
                BrowserSpaceBannerBackground(branding: context.preview { $0.themeMode = .gradient })
                    .frame(width: 56, height: 48).clipShape(.rect(cornerRadius: 8))
            }
        }
    }

    private func slider(
        _ title: LocalizedStringKey, _ path: WritableKeyPath<SpaceBranding, Double>,
        range: ClosedRange<Double> = 0...1, readout: CrestSettingSliderReadout = .percent
    ) -> some View {
        BrowserCrestStudioSlider(title: title, value: context.setting(path), range: range, readout: readout)
    }
}

#if DEBUG
    #Preview("Interactive crest controls") {
        @Previewable @State var branding = BrowserSpaceBrandingPreviewFixture.crestBranding
        Form {
            BrowserCrestStudioColors(
                context: BrowserCrestStudioContext(
                    branding: $branding, defaults: BrowserSpaceBrandingPreviewFixture.crestBranding, compact: false),
                symbol: "crown.fill")
        }.crestSettingsForm().frame(width: 480, height: 650)
    }
#endif
