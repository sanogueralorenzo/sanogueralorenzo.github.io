import SwiftUI

/// Bindings normalize at the editing boundary, shared by setup drafts and live Spaces.
@MainActor
struct BrowserCrestStudioContext {
    let branding: Binding<SpaceBranding>
    let defaults: SpaceBranding
    var compact: Bool
    var previewBranding: SpaceBranding?
    var value: SpaceBranding { branding.wrappedValue }

    func preview(_ mutation: (inout SpaceBranding) -> Void) -> SpaceBranding {
        var candidate = previewBranding ?? value
        candidate.iconStyle = .layeredCrest
        mutation(&candidate)
        return candidate.normalized()
    }

    func crest<Value: Equatable>(_ path: WritableKeyPath<SpaceCrest, Value>) -> CrestSettingValue<Value> {
        CrestSettingValue(
            Binding(
                get: { value.crest[keyPath: path] },
                set: { next in
                    branding.editorUpdate {
                        $0.crest[keyPath: path] = next
                        $0.hasCustomAppearance = true
                    }
                }), default: defaults.crest[keyPath: path])
    }

    func setting<Value: Equatable>(_ path: WritableKeyPath<SpaceBranding, Value>) -> CrestSettingValue<Value> {
        CrestSettingValue(
            Binding(
                get: { value[keyPath: path] },
                set: { next in
                    branding.editorUpdate {
                        $0[keyPath: path] = next
                        $0.hasCustomAppearance = true
                    }
                }), default: defaults[keyPath: path])
    }

    func slider(
        _ title: LocalizedStringKey, _ path: WritableKeyPath<SpaceCrest, Double>,
        range: ClosedRange<Double> = 0...1, readout: CrestSettingSliderReadout = .percent
    ) -> some View {
        BrowserCrestStudioSlider(title: title, value: crest(path), range: range, readout: readout)
    }

    func count(_ title: LocalizedStringKey, _ path: WritableKeyPath<SpaceCrest, Int>, range: ClosedRange<Int>)
        -> some View
    {
        let value = crest(path)
        return CrestSettingRow(title, setting: value.resettable(title)) {
            Stepper(value: value.binding, in: range) { Text(value.wrappedValue.formatted()).monospacedDigit() }
                .fixedSize()
        }
    }

    func picker<Option: Hashable & BrowserSpaceHeraldicTerm>(
        _ title: LocalizedStringKey, _ path: WritableKeyPath<SpaceCrest, Option>, options: [Option]
    ) -> some View {
        let value = crest(path)
        return CrestSettingRow(title, setting: value.resettable(title)) {
            Picker(title, selection: value.binding) {
                ForEach(options, id: \.self) { Text($0.title).tag($0) }
            }
            .labelsHidden()
            #if os(macOS)
                .fixedSize()
            #endif
        }
    }
}

struct BrowserCrestStudioSlider: View {
    @Environment(\.crestStudioEditingChanged) private var editingChanged
    let title: LocalizedStringKey
    let value: CrestSettingValue<Double>
    var range: ClosedRange<Double> = 0...1
    var readout: CrestSettingSliderReadout = .percent

    var body: some View {
        CrestSettingSlider(
            title, value: value, range: range, readout: readout,
            onEditingChanged: editingChanged.callAsFunction
        )
    }
}

/// Small cards keep one scroll owner in Settings and in onboarding.
struct BrowserCrestStudioGroup<Content: View>: View {
    let title: LocalizedStringResource
    let systemImage: String
    var preview: SpaceBranding? = nil
    var symbol: String = "sparkles"
    @ViewBuilder var content: Content

    init(
        title: LocalizedStringResource, systemImage: String, preview: SpaceBranding? = nil, symbol: String = "sparkles",
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.preview = preview
        self.symbol = symbol
        self.content = content()
    }

    /// The group for one step of making a crest, named and marked as the step is.
    init(
        step: BrowserCrestStudioStep, preview: SpaceBranding? = nil, symbol: String = "sparkles",
        @ViewBuilder content: () -> Content
    ) {
        self.init(title: step.title, systemImage: step.symbol, preview: preview, symbol: symbol, content: content)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(title)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                if let preview {
                    BrowserCrestStudioMark(branding: preview, symbol: symbol, size: 56)
                        .frame(width: 72, height: 64)
                        .background { BrowserSpaceBannerBackground(branding: preview) }
                        .clipShape(.rect(cornerRadius: 12))
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            VStack(alignment: .leading, spacing: 16) { content }
                .padding(20)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.primary.opacity(0.035), in: .rect(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(.primary.opacity(0.055))
                .allowsHitTesting(false)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(title))
    }
}

/// Each choice renders the current composition with just this property changed.
struct BrowserCrestStudioGallery<Option: Hashable & BrowserSpaceHeraldicTerm>: View {
    let context: BrowserCrestStudioContext
    let title: LocalizedStringKey
    let path: WritableKeyPath<SpaceCrest, Option>
    let options: [Option]

    var body: some View {
        let value = context.crest(path)
        VStack(alignment: .leading, spacing: 10) {
            CrestSettingRow(title, setting: value.resettable(title)) {
                Text(value.wrappedValue.title).foregroundStyle(.secondary)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 10)], spacing: 10) {
                ForEach(options, id: \.self) { option in
                    BrowserCrestStudioChoice(title: option.title, selected: option == value.wrappedValue) {
                        value.binding.wrappedValue = option
                    } artwork: {
                        BrowserSpaceCrestIcon(
                            branding: context.preview {
                                $0.crest[keyPath: path] = option
                            }, size: 52, rasterizesLayers: false
                        )
                        .equatable()
                    }
                }
            }
        }
    }
}

extension EnvironmentValues {
    @Entry var crestStudioEditingChanged = BrowserCrestStudioEditingAction()
}

struct BrowserCrestStudioEditingAction {
    var update: (Bool) -> Void = { _ in }

    func callAsFunction(_ editing: Bool) { update(editing) }
}

struct BrowserCrestStudioChoice<Artwork: View>: View {
    let title: LocalizedStringResource
    let selected: Bool
    /// The color that marks the chosen tile.
    var tint: Color = CrestBrandTheme.accent
    let select: () -> Void
    @ViewBuilder var artwork: Artwork

    var body: some View {
        Button(action: select) {
            VStack(spacing: 4) {
                artwork.frame(width: 64, height: 58)
                Text(title).font(.caption).lineLimit(2).multilineTextAlignment(.center)
                    .frame(height: 30, alignment: .top)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(
                selected ? tint.opacity(0.12) : .primary.opacity(0.035), in: .rect(cornerRadius: 12)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12).strokeBorder(
                    selected ? tint : .clear, lineWidth: 2)
            }
            .contentShape(.rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(title))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
