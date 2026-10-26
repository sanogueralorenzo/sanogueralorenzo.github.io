import SwiftUI

/// A part of the crest that wears a color of its own.
struct BrowserCrestForgeLayer: Hashable, Identifiable, Sendable {
    // MARK: - Static Variables

    static let field = BrowserCrestForgeLayer(
        slot: 0, title: "Field", index: \.backplateColorIndex, crestStep: .shape,
        crestHint: "Choose a shape to color its field", draws: { $0.backplate != .none })
    static let secondField = BrowserCrestForgeLayer(
        slot: 1, title: "Second field", index: \.secondaryFieldColorIndex, crestStep: .field,
        crestHint: "Divide the field to use a second color",
        draws: { $0.backplate != .none && $0.fieldDivision != .plain })
    static let band = BrowserCrestForgeLayer(
        slot: 2, title: "Band", index: \.ordinaryColorIndex, crestStep: .band,
        crestHint: "Choose a band to color it", draws: { $0.backplate != .none && $0.ordinary != .none })
    static let emblem = BrowserCrestForgeLayer(
        slot: 3, title: "Emblem", index: \.symbolColorIndex, crestStep: .emblem,
        crestHint: "Choose an emblem to color it", draws: { $0.resolvedCharge.kind != .none }, isIconFigure: true)
    static let border = BrowserCrestForgeLayer(
        slot: 4, title: "Border", index: \.trimColorIndex, crestStep: .border,
        crestHint: "Choose a border to color it", draws: { $0.trim != .none })
    static let edge = BrowserCrestForgeLayer(
        slot: 5, title: "Edge", index: \.edgeColorIndex, crestStep: .shape,
        crestHint: "Give the shape an edge to color it",
        draws: { $0.backplate != .none && ($0.edgeWidth > 0 || $0.showsOutline) })

    /// Every layer, in the order its swatches show and its palette entries sit.
    static let all: [BrowserCrestForgeLayer] = [field, secondField, band, emblem, border, edge]

    // MARK: - Variables

    /// The layer's entry in a crest palette with a color for each layer.
    let slot: Int
    let title: LocalizedStringResource

    /// The crest's index into its colors for this layer.
    let index: WritableKeyPath<SpaceCrest, Int> & Sendable

    /// The step that gives a crest this layer, and what to do there, for a
    /// crest that doesn't draw it.
    let crestStep: BrowserCrestStudioStep
    let crestHint: LocalizedStringResource

    /// Whether a crest draws this layer.
    let draws: @Sendable (SpaceCrest) -> Bool

    /// Whether the layer is the figure an icon draws in place of a crest.
    let isIconFigure: Bool

    var id: Int { slot }

    // MARK: - Initializers

    private init(
        slot: Int, title: LocalizedStringResource, index: WritableKeyPath<SpaceCrest, Int> & Sendable,
        crestStep: BrowserCrestStudioStep, crestHint: LocalizedStringResource,
        draws: @escaping @Sendable (SpaceCrest) -> Bool, isIconFigure: Bool = false
    ) {
        self.slot = slot
        self.title = title
        self.index = index
        self.crestStep = crestStep
        self.crestHint = crestHint
        self.draws = draws
        self.isIconFigure = isIconFigure
    }

    // MARK: - Actions - Drawing

    /// The layers whose colors `branding`'s stage shows: every layer of a
    /// crest, drawn or not, or an icon's one figure.
    static func shown(by branding: SpaceBranding) -> [BrowserCrestForgeLayer] {
        branding.iconStyle == .layeredCrest ? all : all.filter(\.isIconFigure)
    }

    /// The layer's name on `branding`'s stage: an icon's figure is its color.
    func title(in branding: SpaceBranding) -> LocalizedStringResource {
        branding.iconStyle == .layeredCrest || !isIconFigure ? title : "Color"
    }

    /// Whether `branding` draws this layer at all. An icon draws only its
    /// figure.
    func isDrawn(by branding: SpaceBranding) -> Bool {
        branding.iconStyle == .layeredCrest ? draws(branding.crest) : isIconFigure
    }

    /// The step that gives `branding` this layer: an icon becomes a crest
    /// under Emblem first.
    func enablingStep(for branding: SpaceBranding) -> BrowserCrestStudioStep {
        branding.iconStyle == .layeredCrest ? crestStep : .emblem
    }

    /// What to do to draw this layer in `branding`.
    func enablingHint(for branding: SpaceBranding) -> LocalizedStringResource {
        branding.iconStyle == .layeredCrest ? crestHint : "Choose Crest under Emblem to color the crest"
    }

    // MARK: - Actions - Identity

    static func == (lhs: BrowserCrestForgeLayer, rhs: BrowserCrestForgeLayer) -> Bool {
        lhs.slot == rhs.slot
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(slot)
    }
}

extension SpaceBranding {
    // MARK: - Crest layers

    func forgeColor(of layer: BrowserCrestForgeLayer) -> BrandColor {
        if iconStyle == .simpleSymbol, layer.isIconFigure { return resolvedSymbolColor }
        let colors = crest.layerColors(spaceColors: self.colors)
        let index = crest[keyPath: layer.index]
        return colors.indices.contains(index) ? colors[index] : colors[0]
    }

    /// Whether every layer already has a palette entry of its own.
    var hasLayeredCrestPalette: Bool {
        crest.palette?.count == BrowserCrestForgeLayer.all.count
            && BrowserCrestForgeLayer.all.allSatisfy { crest[keyPath: $0.index] == $0.slot }
    }

    /// Paints one layer. The first time, the crest takes a palette of its own
    /// with an entry for each layer, copied from what each layer wears, so a
    /// layer's color changes only that layer and never the sidebar.
    mutating func setForgeColor(_ color: BrandColor, of layer: BrowserCrestForgeLayer) {
        hasCustomAppearance = true
        if iconStyle == .simpleSymbol, layer.isIconFigure {
            symbolColor = color
            return
        }
        if !hasLayeredCrestPalette {
            let worn = BrowserCrestForgeLayer.all.map { layer -> BrandColor in
                let colors = crest.layerColors(spaceColors: self.colors)
                let index = crest[keyPath: layer.index]
                return colors.indices.contains(index) ? colors[index] : colors[0]
            }
            crest.palette = ColorPalette(colors: worn)
            for layer in BrowserCrestForgeLayer.all { crest[keyPath: layer.index] = layer.slot }
        }
        crest.palette?[layer.slot] = color
    }

    // MARK: - Sidebar colors

    func forgeColor(of role: BrowserSpaceBrandColorRole) -> BrandColor {
        colors.indices.contains(role.slot) ? colors[role.slot] : (colors.last ?? .indigo)
    }

    /// Paints one sidebar color, giving the Space's palette every role up to
    /// this one.
    mutating func setForgeColor(_ color: BrandColor, of role: BrowserSpaceBrandColorRole) {
        hasCustomAppearance = true
        while colors.count <= role.slot { colors.append(colors.last ?? color) }
        colors[role.slot] = color
    }
}

/// The tinctures the templates are made of, a template to a column, darkest
/// first.
struct BrowserCrestForgePalette: View {
    let title: LocalizedStringResource
    var caption: LocalizedStringResource? = nil
    let color: BrandColor
    let select: (BrandColor) -> Void

    private let houses = SpaceHouse.all

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                if let caption {
                    Text(caption).font(.caption).foregroundStyle(.secondary)
                }
            }
            HStack(alignment: .top, spacing: 6) {
                ForEach(houses, id: \.self) { house in
                    VStack(spacing: 6) {
                        ForEach(house.tinctures, id: \.self) { tincture($0) }
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel(Text(house.title))
                }
            }
            ColorPicker(
                "Custom",
                selection: Binding(get: { color.color }, set: { select(BrandColor(color: $0)) }),
                supportsOpacity: false
            )
        }
        .padding(14)
        .fixedSize()
    }

    private func tincture(_ tincture: BrandColor) -> some View {
        let isSelected = tincture.matches(color)
        return Button {
            select(tincture)
        } label: {
            Circle()
                .fill(tincture.color)
                .frame(width: 24, height: 24)
                .overlay { Circle().strokeBorder(.primary.opacity(0.15)) }
                .padding(3)
                .overlay { Circle().strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2) }
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .help(Text(tincture.title))
        .accessibilityLabel(Text(tincture.title))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
