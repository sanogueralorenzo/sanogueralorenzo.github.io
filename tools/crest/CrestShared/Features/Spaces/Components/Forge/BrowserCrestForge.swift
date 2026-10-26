import SwiftUI

/// A Space's Crest Studio: the crest on the Space's own sidebar field, and
/// one step of its making at a time, beside the window's live sidebar.
struct BrowserCrestForge: View {
    @Binding var branding: SpaceBranding
    @Binding var symbol: String
    @Binding var step: BrowserCrestStudioStep
    /// The Space's name, for a page that doesn't already let a person edit it.
    var name: Binding<String>? = nil
    /// Whether the page lists the steps, each opening on a page of its own,
    /// in place of the step bar: a phone has no room for eight segments.
    var listsSteps = false
    /// Whether the stage carries the step bar; a step's own page has none.
    var showsStepBar = true

    @State private var initialAppearance: SpaceBranding?
    @State private var history: [SpaceBranding] = []
    @State private var editingStart: SpaceBranding?
    /// The look Undo put back, which is not itself a change to remember.
    @State private var restoredBranding: SpaceBranding?
    @State private var choosesEmoji = false

    private var context: BrowserCrestStudioContext {
        BrowserCrestStudioContext(
            branding: $branding,
            defaults: branding.startingLook ?? initialAppearance ?? branding,
            compact: false, previewBranding: editingStart)
    }

    private var isIcon: Bool { branding.iconStyle == .simpleSymbol }

    /// The step shown: the one chosen, unless an icon has no use for it.
    private var shownStep: BrowserCrestStudioStep {
        isIcon && step.isCrestOnly ? .emblem : step
    }

    var body: some View {
        BrowserSettingsPane(.spaces) {
            if listsSteps {
                stepList
            } else {
                stepSections
            }
        }
        #if os(iOS)
            .modifier(
                BrowserCrestForgeStepPages(isEnabled: listsSteps) { step in
                    BrowserCrestForge(branding: $branding, symbol: $symbol, step: .constant(step), showsStepBar: false)
                        .navigationTitle(Text(step.title))
                        .navigationBarTitleDisplayMode(.inline)
                })
        #endif
        #if os(macOS)
            .environment(\.browserSettingsColumnWidth, BrowserCrestForgeMetrics.columnWidth)
        #endif
        .environment(
            \.crestStudioEditingChanged,
            BrowserCrestStudioEditingAction { editing in
                // A drag is one change to undo, and the galleries keep their
                // compositions while it runs.
                if editing {
                    if editingStart == nil { editingStart = branding }
                } else if let start = editingStart {
                    editingStart = nil
                    if start != branding { remember(start) }
                }
            }
        )
        .onAppear { if initialAppearance == nil { initialAppearance = branding } }
        .onChange(of: branding) { previous, current in
            if let restored = restoredBranding {
                restoredBranding = nil
                if current == restored { return }
            }
            guard editingStart == nil else { return }
            remember(previous)
        }
        .accessibilityIdentifier("space-customization-controls")
    }

    // MARK: - Steps

    /// The stage over every step, each showing what it has chosen.
    private var stepList: some View {
        Section {
            ForEach(BrowserCrestStudioStep.all) { step in
                NavigationLink(value: step) {
                    LabeledContent {
                        Text(step.summary(branding))
                    } label: {
                        Label {
                            Text(step.title)
                        } icon: {
                            Image(systemName: step.symbol)
                        }
                    }
                }
                .disabled(isIcon && step.isCrestOnly)
                .accessibilityIdentifier("space-forge-step-\(step.name)")
            }
        } header: {
            stageHeader
        }
    }

    @ViewBuilder
    private var stepSections: some View {
        switch shownStep.kind {
        case .start:
            startSections
        case .shape:
            shapeSections
        case .field:
            fieldSections
        case .band:
            bandSections
        case .emblem:
            emblemSections
        case .border:
            borderSections
        case .finish:
            finishSections
        case .sidebar:
            sidebarSections
        }
    }

    // MARK: - Step sections

    private var startSections: some View {
        gallery(SpaceHouse.all, id: \.self) { house in
            BrowserCrestStudioChoice(title: house.title, selected: house.isWorn(by: branding), tint: .accentColor) {
                branding = house.applying(to: branding)
            } artwork: {
                crest(house.applying(to: editingStart ?? branding))
            }
        } trailing: {
            ForEach(SpaceScheme.all, id: \.self) { scheme in
                BrowserSpaceSchemeChoice(scheme: scheme, branding: $branding, symbol: symbol, tint: .accentColor)
            }
        }
    }

    @ViewBuilder
    private var shapeSections: some View {
        crestGallery(\.backplate, CrestBackplate.all)
        Section {
            context.slider("Edge", \.edgeWidth, range: CrestMeasure.edgeWidth.range)
            context.slider("Size", \.plateScale, range: CrestMeasure.plateScale.range)
            if branding.crest.backplate.hasTeeth {
                context.count("Teeth", \.sealTeeth, range: CrestMeasure.sealTeeth.countRange)
            }
        }
    }

    @ViewBuilder
    private var fieldSections: some View {
        crestGallery(\.fieldDivision, CrestFieldDivision.all)
        Section {
            context.count("Repeats", \.divisionCount, range: CrestMeasure.divisionCount.countRange)
                .disabled(!branding.crest.fieldDivision.isCounted)
        }
    }

    @ViewBuilder
    private var bandSections: some View {
        crestGallery(\.ordinary, CrestOrdinary.all)
        Section {
            context.slider("Width", \.ordinaryWidth, range: CrestMeasure.ordinaryWidth.range)
                .disabled(branding.crest.ordinary == .none)
        }
    }

    @ViewBuilder
    private var emblemSections: some View {
        Section {
            identityRow
        } header: {
            stageHeader
        }
        if isIcon {
            iconSections
        } else {
            Section {
                BrowserCrestStudioEmblem(context: context, symbol: symbol, isEmbedded: true)
            }
        }
    }

    @ViewBuilder
    private var borderSections: some View {
        crestGallery(\.trim, CrestTrim.all)
        Section {
            context.slider("Weight", \.trimWeight, range: CrestMeasure.trimWeight.range)
                .disabled(branding.crest.trim == .none)
            context.count("Details", \.trimDetail, range: CrestMeasure.trimDetail.countRange)
                .disabled(!branding.crest.trim.isCounted)
        }
    }

    @ViewBuilder
    private var finishSections: some View {
        crestGallery(\.finish, CrestFinish.all)
        Section {
            segmented("Shadow", context.crest(\.depth), options: CrestDepth.all)
            let outline = context.crest(\.showsOutline)
            CrestSettingRow("Outline", setting: outline.resettable("Outline")) {
                Toggle("Outline", isOn: outline.binding).labelsHidden()
            }
            if branding.crest.finish.hasAngle {
                context.slider(
                    "Sheen angle", \.sheenAngle, range: CrestMeasure.sheenAngle.range,
                    readout: .init { "\(Int($0))°" })
            }
        }
    }

    @ViewBuilder
    private var sidebarSections: some View {
        sidebarGallery
        sidebarSection
    }

    private var identityRow: some View {
        let style = context.setting(\.iconStyle)
        return CrestSettingRow("Identity", setting: style.resettable("Identity")) {
            Picker("Identity", selection: style.binding) {
                Text("Crest").tag(SpaceIconStyle.layeredCrest)
                Text("Icon").tag(SpaceIconStyle.simpleSymbol)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            #if os(macOS)
                .fixedSize()
            #endif
            .accessibilityIdentifier("space-forge-identity")
        }
    }

    @ViewBuilder
    private var iconSections: some View {
        Section {
            BrowserSystemSymbolPicker(
                selection: Binding(
                    get: { BrowserIconSymbol.emoji(from: symbol) == nil ? symbol : "" },
                    set: { symbol = $0 }))
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
    }

    private var sidebarGallery: some View {
        gallery(SpaceBannerPattern.all.map(Optional.some) + [nil], id: \.self) { pattern in
            let selected =
                pattern.map { branding.themeMode == .banner && branding.bannerPattern == $0 }
                ?? (branding.themeMode == .gradient)
            BrowserCrestStudioChoice(
                title: pattern?.title ?? "Gradient", selected: selected, tint: .accentColor
            ) {
                context.branding.editorUpdate {
                    if let pattern {
                        $0.themeMode = .banner
                        $0.bannerPattern = pattern
                    } else {
                        $0.themeMode = .gradient
                    }
                    $0.hasCustomAppearance = true
                }
            } artwork: {
                BrowserSpaceBannerBackground(
                    branding: context.preview {
                        if let pattern {
                            $0.themeMode = .banner
                            $0.bannerPattern = pattern
                        } else {
                            $0.themeMode = .gradient
                        }
                    }
                )
                .frame(width: 56, height: 48)
                .clipShape(.rect(cornerRadius: 8))
            }
        }
    }

    private var sidebarSection: some View {
        Section {
            BrowserCrestStudioSlider(title: "Intensity", value: context.setting(\.bannerStrength))
            if branding.themeMode == .gradient {
                let angle = context.setting(\.gradientAngle)
                CrestSettingRow("Gradient angle", setting: angle.resettable("Gradient angle")) {
                    HStack(spacing: 12) {
                        Text("\(Int(angle.wrappedValue.rounded()))°").monospacedDigit().foregroundStyle(.secondary)
                        BrowserSpaceGradientAngleDial(angle: angle.binding, color: branding.secondaryColor.color)
                            .frame(width: 44, height: 44)
                    }
                }
            }
            BrowserCrestStudioSlider(title: "Readability fade", value: context.setting(\.readabilityFade))
            BrowserCrestStudioSlider(title: "Folder colors", value: context.setting(\.folderColorIntensity))
            let texture = context.setting(\.showsTexture)
            CrestSettingRow("Texture", setting: texture.resettable("Texture")) {
                Toggle("Texture", isOn: texture.binding).labelsHidden()
            }
            segmentedText
        }
    }

    private var segmentedText: some View {
        let text = context.setting(\.textColorMode)
        return CrestSettingRow("Text", setting: text.resettable("Text")) {
            Picker("Text", selection: text.binding) {
                ForEach(SpaceTextColorMode.all, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            #if os(macOS)
                .fixedSize()
            #endif
        }
    }

    // MARK: - Galleries

    private func crestGallery<Option: Hashable & BrowserSpaceHeraldicTerm>(
        _ path: WritableKeyPath<SpaceCrest, Option>, _ options: [Option]
    ) -> some View {
        let value = context.crest(path)
        return gallery(options, id: \.self) { option in
            BrowserCrestStudioChoice(title: option.title, selected: option == value.wrappedValue, tint: .accentColor) {
                value.binding.wrappedValue = option
            } artwork: {
                crest(context.preview { $0.crest[keyPath: path] = option })
            }
        }
    }

    private func gallery<Item, ID: Hashable, Tile: View>(
        _ items: [Item], id: KeyPath<Item, ID>, @ViewBuilder tile: @escaping (Item) -> Tile
    ) -> some View {
        gallery(items, id: id, tile: tile) { EmptyView() }
    }

    /// A gallery of `items`' tiles followed by `trailing` tiles of another kind.
    private func gallery<Item, ID: Hashable, Tile: View, Trailing: View>(
        _ items: [Item], id: KeyPath<Item, ID>, @ViewBuilder tile: @escaping (Item) -> Tile,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        Section {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 80), spacing: 8)], spacing: 8
            ) {
                ForEach(items, id: id) { item in tile(item) }
                trailing()
            }
            .padding(.vertical, 4)
            .accessibilityIdentifier("space-forge-gallery")
        } header: {
            stageHeader
        }
    }

    /// The stage and the steps head the page's first section, outside the
    /// grouped boxes, so the crest sits on the Space's field alone.
    private var stageHeader: some View {
        VStack(spacing: 16) {
            BrowserCrestForgeStage(
                branding: $branding, symbol: symbol, name: name, canUndo: !history.isEmpty, shuffle: shuffle,
                undo: undo, openStep: { step = $0 })
            if showsStepBar && !listsSteps {
                BrowserPlatformCrestForgeStepBar(
                    step: Binding(get: { shownStep }, set: { step = $0 }),
                    disabledSteps: isIcon ? Set(BrowserCrestStudioStep.all.filter(\.isCrestOnly)) : [])
            }
        }
        .textCase(nil)
        .padding(.bottom, 4)
    }

    private func crest(_ look: SpaceBranding) -> some View {
        BrowserSpaceCrestIcon(branding: look, size: BrowserCrestForgeMetrics.tileCrestSize, rasterizesLayers: false)
            .equatable()
    }

    private func segmented<Option: Hashable & BrowserSpaceHeraldicTerm>(
        _ title: LocalizedStringKey, _ value: CrestSettingValue<Option>, options: [Option]
    ) -> some View {
        CrestSettingRow(title, setting: value.resettable(title)) {
            Picker(title, selection: value.binding) {
                ForEach(options, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            #if os(macOS)
                .fixedSize()
            #endif
        }
    }

    // MARK: - History

    private func remember(_ previous: SpaceBranding) {
        history.append(previous)
        if history.count > BrowserCrestForgeHistory.limit { history.removeFirst() }
    }

    private func undo() {
        guard let previous = history.popLast() else { return }
        restoredBranding = previous
        branding = previous
    }

    private func shuffle() {
        branding = Self.shuffled(branding)
    }

    // MARK: - Looks

    /// A new crest and sidebar, every part chosen afresh, in the templates'
    /// tinctures: a dark color for the field, a second for its division, and
    /// light ones for the charges on it, so a light color always sits on a
    /// dark one; the sidebar in dark ones.
    static func shuffled(_ branding: SpaceBranding) -> SpaceBranding {
        let tinctures = Tincture.all.map(\.color)
        let darks = tinctures.filter { $0.luminance < 0.3 }.shuffled()
        let lights = tinctures.filter { $0.luminance > 0.42 }.shuffled()
        guard darks.count > 2, lights.count > 1 else { return branding }
        let chance = { (odds: Double) in Double.random(in: 0..<1) < odds }

        var look = branding
        look.iconStyle = .layeredCrest
        var crest = look.crest
        crest.backplate = CrestBackplate.all.filter { $0 != .none }.randomElement() ?? .shield
        crest.plateScale = 1
        crest.sealTeeth = Int.random(in: 10...18)
        crest.fieldDivision = chance(0.4) ? .plain : CrestFieldDivision.all.filter { $0 != .plain }.randomElement()!
        crest.divisionCount = Int.random(in: CrestMeasure.divisionCount.countRange.lowerBound...6)
        crest.ordinary = chance(0.5) ? .none : CrestOrdinary.all.filter { $0 != .none }.randomElement()!
        crest.ordinaryWidth = Double.random(in: 0.8...1.2)
        crest.symbol = CrestSymbol.selectable.randomElement() ?? .dragon
        crest.charge = nil
        crest.chargeLayout = chance(0.75) ? .single : [.paired, .trio].randomElement()!
        crest.chargeScale = crest.chargeLayout == .single ? Double.random(in: 1.05...1.3) : Double.random(in: 0.9...1.1)
        crest.chargeOffset = 0
        crest.trim = CrestTrim.all.randomElement() ?? .none
        crest.trimWeight = Double.random(in: 0.6...1.1)
        crest.trimDetail = Int.random(in: 10...18)
        crest.edgeWidth = chance(0.5) ? 0 : Double.random(in: 0.2...0.45)
        crest.showsOutline = chance(0.2)
        crest.finish = [.flat, .flat, .sheen, .embossed].randomElement()!
        crest.depth = CrestDepth.all.randomElement() ?? .soft
        let field = darks[0]
        let second = darks[1]
        let metal = lights[0]
        let border = chance(0.6) ? metal : lights[1]
        crest.palette = [field, second, metal, metal, border, darks[2]]
        for layer in BrowserCrestForgeLayer.all { crest[keyPath: layer.index] = layer.slot }
        look.crest = crest

        look.themeMode = chance(0.15) ? .gradient : .banner
        look.bannerPattern = SpaceBannerPattern.all.randomElement() ?? .diagonal
        look.gradientAngle = Double(Int.random(in: 0..<8) * 45)
        // The sidebar keeps to dark tinctures, as the templates do, so its
        // text stays light over every band of the pattern.
        look.colors = [darks[2], field, second]
        look.hasCustomAppearance = true
        return look.normalized()
    }
}

private enum BrowserCrestForgeHistory {
    static let limit = 40
}

#if os(iOS)
    /// Opens a listed step on a page of its own, where the Forge lists its steps.
    private struct BrowserCrestForgeStepPages<Page: View>: ViewModifier {
        let isEnabled: Bool
        @ViewBuilder let page: (BrowserCrestStudioStep) -> Page

        func body(content: Content) -> some View {
            if isEnabled {
                content.navigationDestination(for: BrowserCrestStudioStep.self, destination: page)
            } else {
                content
            }
        }
    }
#endif
