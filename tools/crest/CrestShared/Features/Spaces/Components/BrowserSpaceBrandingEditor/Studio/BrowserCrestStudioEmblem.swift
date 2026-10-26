import SwiftUI

struct BrowserCrestStudioEmblem: View {
    let context: BrowserCrestStudioContext
    let symbol: String
    /// Shows the controls without their card or color row, for a studio
    /// that frames them and paints the emblem elsewhere.
    let isEmbedded: Bool
    @State private var source: CrestChargeKind
    // The fields each emblem source edits, kept while another source is shown.
    @State var search = ""
    @State var showsAll = false
    @State var systemName = "sparkles"
    @State var emoji = "🦁"
    @State var monogram = "C"
    @State var monogramStyle = CrestMonogramStyle.serif
    @State var choosesEmoji = false

    init(context: BrowserCrestStudioContext, symbol: String, isEmbedded: Bool = false) {
        self.context = context
        self.symbol = symbol
        self.isEmbedded = isEmbedded
        _source = State(initialValue: context.value.crest.resolvedCharge.kind)
    }

    var body: some View {
        Group {
            if isEmbedded {
                VStack(alignment: .leading, spacing: 16) { controls }
            } else {
                BrowserCrestStudioGroup(step: .emblem, preview: context.compact ? context.value : nil, symbol: symbol) {
                    controls
                }
            }
        }
        .onAppear { load(context.value.crest.resolvedCharge) }
        .onChange(of: source) { _, _ in commitSource() }
        .onChange(of: context.value.crest.resolvedCharge) { _, charge in
            // Empty in-progress text stays editable instead of removing its field.
            if charge != CrestCharge.none { load(charge) }
        }
        .onChange(of: systemName) { _, _ in if source == .system { commitSource() } }
        .onChange(of: emoji) { _, _ in if source == .emoji { commitSource() } }
        .onChange(of: monogram) { _, _ in if source == .monogram { commitSource() } }
        .onChange(of: monogramStyle) { _, _ in if source == .monogram { commitSource() } }
    }

    @ViewBuilder private var controls: some View {
        let value = context.crest(\.charge)
        CrestSettingRow("Source", setting: value.resettable("Emblem")) {
            Picker("Emblem source", selection: $source) {
                ForEach(CrestChargeKind.all, id: \.self) { Text($0.title).tag($0) }
            }.labelsHidden().fixedSize()
        }
        sourceControls
        if source != .none {
            if source.isTinted, !isEmbedded {
                BrowserCrestStudioColorRow(context: context, title: "Emblem color", path: \.symbolColorIndex)
            }
            context.picker("Arrangement", \.chargeLayout, options: CrestChargeLayout.all)
            context.slider("Size", \.chargeScale, range: CrestMeasure.chargeScale.range)
            context.slider("Vertical offset", \.chargeOffset, range: CrestMeasure.chargeOffset.range)
            if source.takesWeight, source != .heraldic || context.value.crest.symbol.assetName == nil {
                context.picker("Weight", \.chargeWeight, options: CrestChargeWeight.all)
            }
        }
    }

    @ViewBuilder private var sourceControls: some View {
        switch source.kind {
        case .heraldic:
            BrowserCrestStudioHeraldicEmblemControls(context: context, search: $search, showsAll: $showsAll)
        case .system:
            BrowserSystemSymbolPicker(selection: $systemName)
        case .emoji:
            BrowserCrestStudioEmojiEmblemControls(emoji: $emoji, choosesEmoji: $choosesEmoji)
        case .monogram:
            BrowserCrestStudioMonogramEmblemControls(monogram: $monogram, monogramStyle: $monogramStyle)
        case .none:
            EmptyView()
        }
    }

    private func commitSource() {
        context.crest(\.charge).binding.wrappedValue = source.studioSource.charge(in: self)
    }

    private func load(_ charge: CrestCharge) {
        source = charge.kind
        charge.kind.studioSource.load(charge, into: self)
    }
}

#if DEBUG
    #Preview("Interactive crest controls") {
        @Previewable @State var branding = BrowserSpaceBrandingPreviewFixture.crestBranding
        Form {
            BrowserCrestStudioEmblem(
                context: BrowserCrestStudioContext(
                    branding: $branding, defaults: BrowserSpaceBrandingPreviewFixture.crestBranding, compact: false),
                symbol: "crown.fill")
        }.crestSettingsForm().frame(width: 480, height: 650)
    }
#endif
