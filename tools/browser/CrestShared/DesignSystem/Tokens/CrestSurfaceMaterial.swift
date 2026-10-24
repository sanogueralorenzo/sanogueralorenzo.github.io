import SwiftUI

/// The material every sidebar layer above the base UI is drawn with: pinned
/// tiles, the selected tab, folders, Split View groups, the address field, the
/// extension strip and widget cards.
///
/// One choice for the whole device, made in Look and Feel and handed down
/// through ``SwiftUI/EnvironmentValues/crestSurfaceMaterial``. Reduce
/// Transparency renders every member opaque on its own.
struct CrestSurfaceMaterial: Hashable, Sendable {
    // MARK: - Static Variables

    static let ultraThin = CrestSurfaceMaterial(
        name: "ultraThin", title: "Ultra Thin", material: .ultraThinMaterial)
    static let thin = CrestSurfaceMaterial(name: "thin", title: "Thin", material: .thinMaterial)
    static let regular = CrestSurfaceMaterial(name: "regular", title: "Regular", material: .regularMaterial)
    static let thick = CrestSurfaceMaterial(name: "thick", title: "Thick", material: .thickMaterial)
    static let ultraThick = CrestSurfaceMaterial(
        name: "ultraThick", title: "Ultra Thick", material: .ultraThickMaterial)
    /// From the most see-through to the most solid.
    static let all = [ultraThin, thin, regular, thick, ultraThick]
    static let standard = regular

    // MARK: - Variables

    /// The persisted spelling.
    let name: String
    let title: LocalizedStringResource
    let material: Material

    /// Where this material sits in ``all``.
    var position: Int { Self.all.firstIndex(of: self) ?? 0 }

    // MARK: - Initializers

    private init(name: String, title: LocalizedStringResource, material: Material) {
        self.name = name
        self.title = title
        self.material = material
    }

    // MARK: - Actions - Lookup

    static func named(_ name: String?) -> CrestSurfaceMaterial? {
        all.first { $0.name == name }
    }

    /// The material at `position` in ``all``, held to its ends.
    static func at(position: Int) -> CrestSurfaceMaterial {
        all[min(max(position, 0), all.count - 1)]
    }
}

// MARK: - Hashable

extension CrestSurfaceMaterial {
    static func == (lhs: CrestSurfaceMaterial, rhs: CrestSurfaceMaterial) -> Bool {
        lhs.name == rhs.name
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }
}

extension EnvironmentValues {
    /// Set at each window root from the device's appearance choice.
    @Entry var crestSurfaceMaterial = CrestSurfaceMaterial.standard
}
