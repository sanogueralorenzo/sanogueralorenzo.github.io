import Foundation

/// The halves of a Space's editor on iPhone and iPad.
struct BrowserSpaceEditorSection: Hashable, Identifiable, Sendable {
    // MARK: - Types

    /// Each half shows its own pane, so the editor switches over the kind.
    enum Kinds: Sendable {
        case appearance
        case settings
    }

    // MARK: - Static Variables

    static let appearance = BrowserSpaceEditorSection(kind: .appearance, name: "appearance", title: "Appearance")
    static let settings = BrowserSpaceEditorSection(kind: .settings, name: "settings", title: "Details")

    /// Every half, in the picker's order.
    static let all: [BrowserSpaceEditorSection] = [appearance, settings]

    // MARK: - Variables

    let kind: Kinds
    let name: String
    let title: LocalizedStringResource

    var id: String { name }

    // MARK: - Initializers

    private init(kind: Kinds, name: String, title: LocalizedStringResource) {
        self.kind = kind
        self.name = name
        self.title = title
    }

    // MARK: - Actions - Identity

    static func == (lhs: BrowserSpaceEditorSection, rhs: BrowserSpaceEditorSection) -> Bool {
        lhs.name == rhs.name
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }
}
