import Foundation

/// The steps of making a crest, in the order arms are composed: the Forge's
/// step bar on the Mac, and the Studio's groups everywhere.
struct BrowserCrestStudioStep: Hashable, Identifiable, Sendable {
    // MARK: - Types

    /// Each step shows its own choices. ``BrowserCrestForge`` switches on the
    /// kind to choose that step's concrete sections.
    enum Kinds: Sendable {
        case start
        case shape
        case field
        case band
        case emblem
        case border
        case finish
        case sidebar
    }

    // MARK: - Static Variables

    static let start = BrowserCrestStudioStep(
        kind: .start, name: "start", title: "Start from", symbol: "sparkles", isCrestOnly: false,
        summary: { branding in
            SpaceHouse.all.first { $0.isWorn(by: branding) }?.title
                ?? SpaceScheme.all.first { $0.isWorn(by: branding) }?.title ?? "Custom"
        })
    static let shape = BrowserCrestStudioStep(
        kind: .shape, name: "shape", title: "Shape", symbol: "shield", isCrestOnly: true,
        summary: { $0.crest.backplate.title })
    static let field = BrowserCrestStudioStep(
        kind: .field, name: "field", title: "Field", symbol: "square.grid.2x2", isCrestOnly: true,
        summary: { $0.crest.fieldDivision.title })
    static let band = BrowserCrestStudioStep(
        kind: .band, name: "band", title: "Band", symbol: "rectangle.center.inset.filled", isCrestOnly: true,
        summary: { $0.crest.ordinary.title })
    static let emblem = BrowserCrestStudioStep(
        kind: .emblem, name: "emblem", title: "Emblem", symbol: "seal", isCrestOnly: false,
        summary: { branding in
            guard branding.iconStyle == .layeredCrest else { return "Icon" }
            let charge = branding.crest.resolvedCharge
            return charge.kind == .heraldic ? (charge.symbol ?? branding.crest.symbol).title : charge.kind.title
        })
    static let border = BrowserCrestStudioStep(
        kind: .border, name: "border", title: "Border", symbol: "square.dashed", isCrestOnly: true,
        summary: { $0.crest.trim.title })
    static let finish = BrowserCrestStudioStep(
        kind: .finish, name: "finish", title: "Finish", symbol: "light.max", isCrestOnly: true,
        summary: { $0.crest.finish.title })
    static let sidebar = BrowserCrestStudioStep(
        kind: .sidebar, name: "sidebar", title: "Sidebar", symbol: "sidebar.left", isCrestOnly: false,
        summary: { $0.themeMode == .gradient ? "Gradient" : $0.bannerPattern.title })

    /// Every step, in the step bar's order.
    static let all: [BrowserCrestStudioStep] = [start, shape, field, band, emblem, border, finish, sidebar]

    // MARK: - Variables

    let kind: Kinds
    let name: String
    let title: LocalizedStringResource
    let symbol: String

    /// Whether the step shapes only a crest, so an icon has no use for it.
    let isCrestOnly: Bool

    /// What a branding has chosen at this step, in a word or two.
    let summary: @Sendable (SpaceBranding) -> LocalizedStringResource

    var id: String { name }

    // MARK: - Initializers

    private init(
        kind: Kinds, name: String, title: LocalizedStringResource, symbol: String, isCrestOnly: Bool,
        summary: @escaping @Sendable (SpaceBranding) -> LocalizedStringResource
    ) {
        self.kind = kind
        self.name = name
        self.title = title
        self.symbol = symbol
        self.isCrestOnly = isCrestOnly
        self.summary = summary
    }

    // MARK: - Actions - Identity

    static func == (lhs: BrowserCrestStudioStep, rhs: BrowserCrestStudioStep) -> Bool {
        lhs.name == rhs.name
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }
}
