import SwiftUI

/// The same live designer edits in-memory setup drafts and persisted Space bindings.
struct BrowserSpaceBrandingEditor: View {
    @Binding var branding: SpaceBranding
    @Binding var symbol: String
    var previewName = ""
    var compact = false
    var showsPreview = true
    var editableName: Binding<String>? = nil
    @Environment(\.browserSettingsUsesLiveSidebar) private var usesLiveSidebar
    @State private var initialAppearance: SpaceBranding?
    @State private var beforeShuffle: SpaceBranding?
    @State private var gesturePreview: SpaceBranding?
    @State private var choosesIdentityEmoji = false

    private var defaults: SpaceBranding {
        branding.startingLook ?? initialAppearance ?? branding
    }

    private var context: BrowserCrestStudioContext {
        BrowserCrestStudioContext(
            branding: $branding, defaults: defaults, compact: compact, previewBranding: gesturePreview)
    }

    var body: some View {
        // Keep section heights stable while the nested galleries lay out during scrolling.
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 20) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Crest Studio").font(CrestTypography.display(28))
                    HStack {
                        Button("Shuffle", systemImage: "shuffle", action: shuffle).buttonStyle(.borderless)
                        if beforeShuffle != nil {
                            Button("Undo shuffle", systemImage: "arrow.uturn.backward") {
                                if let beforeShuffle { branding = beforeShuffle }
                                beforeShuffle = nil
                            }.labelStyle(.iconOnly).buttonStyle(.borderless)
                        }
                    }
                }
                Spacer(minLength: 0)
                if usesLiveSidebar && showsPreview {
                    BrowserCrestStudioMark(branding: branding, symbol: symbol, size: 140)
                }
            }
            if showsPreview && !usesLiveSidebar {
                BrowserCrestStudioPreview(branding: branding, symbol: symbol, name: previewName, compact: true)
            }
            presets
            identity
            if branding.iconStyle == .layeredCrest {
                BrowserCrestStudioColors(context: context, symbol: symbol)
                BrowserCrestStudioComposition(context: context, symbol: symbol)
                BrowserCrestStudioEmblem(context: context, symbol: symbol)
                BrowserCrestStudioOrnaments(context: context, symbol: symbol)
            }
            BrowserCrestStudioBackground(context: context, symbol: symbol)
            Text("Tab, address bar, and sidebar sizing are in Look and Feel. These choices belong to this Space.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Reset appearance to starting point") {
                    branding = defaults
                    beforeShuffle = nil
                }
                .buttonStyle(.borderless).disabled(branding == defaults)
                Spacer()
            }
            DisclosureGroup("Artwork credits") {
                Text(BrowserCrestStudioAppearance.credits).font(.caption).foregroundStyle(.secondary).textSelection(
                    .enabled)
            }.font(.caption)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { if initialAppearance == nil { initialAppearance = branding } }
        .environment(
            \.crestStudioEditingChanged,
            BrowserCrestStudioEditingAction { editing in
                // The actual crest and browser stay live. Choice thumbnails don't
                // need to rebuild their entire compositions for every drag sample.
                gesturePreview = editing ? branding : nil
            }
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Crest Studio")
    }

    private var presets: some View {
        BrowserCrestStudioGroup(step: .start) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 10)], spacing: 10) {
                ForEach(SpaceHouse.all, id: \.self) { house in
                    BrowserCrestStudioChoice(title: house.title, selected: house.isWorn(by: branding)) {
                        branding = house.applying(to: branding)
                        beforeShuffle = nil
                    } artwork: {
                        BrowserSpaceCrestIcon(
                            branding: house.applying(to: gesturePreview ?? branding), size: 52, rasterizesLayers: false
                        )
                        .equatable()
                    }
                }
                ForEach(SpaceScheme.all, id: \.self) { scheme in
                    BrowserSpaceSchemeChoice(scheme: scheme, branding: $branding, symbol: symbol, size: 52)
                }
            }
            Text("Choose a starting point, then make it yours. Reset controls return to this preset.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var identity: some View {
        BrowserCrestStudioGroup(
            title: "Identity", systemImage: "person.crop.square", preview: compact ? branding : nil, symbol: symbol
        ) {
            if let editableName {
                BrowserCrestStudioTextField(
                    title: "Space name", symbol: "rectangle.and.pencil.and.ellipsis", text: editableName)
            }
            Picker("Identity style", selection: context.setting(\.iconStyle).binding) {
                Text("Crest").tag(SpaceIconStyle.layeredCrest)
                Text("Icon").tag(SpaceIconStyle.simpleSymbol)
            }.pickerStyle(.segmented)
            if branding.iconStyle == .simpleSymbol {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) {
                        identitySymbolPicker.frame(minWidth: 220)
                        identityEmojiPicker.frame(minWidth: 220)
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        identitySymbolPicker
                        identityEmojiPicker
                    }
                }
                Toggle(
                    "Follow Space color",
                    isOn: Binding(
                        get: { branding.symbolColor == nil },
                        set: {
                            context.setting(\.symbolColor).binding.wrappedValue = $0 ? nil : branding.primaryColor
                        })
                ).toggleStyle(.switch)
                if branding.symbolColor != nil {
                    ColorPicker(
                        "Icon color",
                        selection: Binding(
                            get: { branding.resolvedSymbolColor.color },
                            set: {
                                context.setting(\.symbolColor).binding.wrappedValue = BrandColor(color: $0)
                            }), supportsOpacity: false)
                }
            }
        }
    }

    private var identitySymbolPicker: some View {
        BrowserSystemSymbolPicker(
            selection: Binding(
                get: { BrowserIconSymbol.emoji(from: symbol) == nil ? symbol : "" },
                set: { symbol = $0 }
            ))
    }

    private var identityEmojiPicker: some View {
        BrowserArtworkPickerButton(
            title: "Emoji",
            detail: BrowserIconSymbol.emoji(from: symbol) == nil ? Text("Choose an emoji") : Text("Change emoji")
        ) {
            choosesIdentityEmoji = true
        } artwork: {
            if let emoji = BrowserIconSymbol.emoji(from: symbol) {
                Text(emoji)
            } else {
                Image(systemName: "face.smiling")
            }
        }
        .accessibilityLabel("Choose Emoji")
        .accessibilityValue(BrowserIconSymbol.emoji(from: symbol) ?? "")
        .browserIconCustomizationPopover(
            .init(
                isPresented: $choosesIdentityEmoji, title: "Space Icon",
                currentEmoji: BrowserIconSymbol.emoji(from: symbol),
                setEmoji: { symbol = BrowserIconSymbol.symbol(forEmoji: $0) }
            ))
    }

    private func shuffle() {
        beforeShuffle = branding
        branding = BrowserCrestStudioAppearance.shuffle(branding)
    }

}

#Preview("Crest Studio") {
    @Previewable @State var branding = BrowserSpaceBrandingPreviewFixture.crestBranding
    @Previewable @State var symbol = BrowserSpaceSimpleSymbol.work.symbol
    ScrollView { BrowserSpaceBrandingEditor(branding: $branding, symbol: $symbol).padding(20) }
        .frame(width: 560, height: 720)
}
