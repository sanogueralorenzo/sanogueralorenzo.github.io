import Foundation

enum BrowserSpaceForegroundTone: Equatable, Sendable {
    case light
    case dark
}

/// A color of the Space's sidebar, by what it paints there and its place in
/// the Space's palette.
struct BrowserSpaceBrandColorRole: Hashable, Identifiable, Sendable {
    // MARK: - Static Variables

    static let background = BrowserSpaceBrandColorRole(
        slot: 0, name: "background", title: "Background", caption: "The sidebar behind your tabs",
        addTitle: "Add Background Color", removeTitle: "Remove Background Color")
    static let accent = BrowserSpaceBrandColorRole(
        slot: 1, name: "accent", title: "Accent",
        caption: "Selected tabs, pins, the address field and the Space picker",
        addTitle: "Add Accent Color", removeTitle: "Remove Accent Color")
    static let pattern = BrowserSpaceBrandColorRole(
        slot: 2, name: "pattern", title: "Pattern", caption: "The pattern’s last band and the gradient’s end",
        addTitle: "Add Pattern Color", removeTitle: "Remove Pattern Color")

    /// Every role, in palette order.
    static let all: [BrowserSpaceBrandColorRole] = [background, accent, pattern]

    // MARK: - Variables

    /// The role's place in the Space's colors.
    let slot: Int
    let name: String
    let title: LocalizedStringResource

    /// What the color paints, in one line.
    let caption: LocalizedStringResource
    let addTitle: LocalizedStringResource
    let removeTitle: LocalizedStringResource

    var id: Int { slot }

    // MARK: - Initializers

    private init(
        slot: Int, name: String, title: LocalizedStringResource, caption: LocalizedStringResource,
        addTitle: LocalizedStringResource, removeTitle: LocalizedStringResource
    ) {
        self.slot = slot
        self.name = name
        self.title = title
        self.caption = caption
        self.addTitle = addTitle
        self.removeTitle = removeTitle
    }

    // MARK: - Actions - Identity

    static func == (lhs: BrowserSpaceBrandColorRole, rhs: BrowserSpaceBrandColorRole) -> Bool {
        lhs.slot == rhs.slot
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(slot)
    }
}

extension SpaceTextColorMode {
    /// The tone a Space's text keeps whatever its colors, or `system`, the
    /// tone the device's appearance reads in, when it follows the device;
    /// automatic works it out from them.
    func foregroundTone(system: BrowserSpaceForegroundTone) -> BrowserSpaceForegroundTone? {
        switch self.kind {
        case .automatic: nil
        case .light: .light
        case .dark: .dark
        case .system: system
        }
    }
}
