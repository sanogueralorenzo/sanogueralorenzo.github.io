import SwiftUI

extension Binding where Value == SpaceBranding {
    func editorColor(for role: BrowserSpaceBrandColorRole) -> Binding<Color>? {
        let index = role.slot
        guard wrappedValue.colors.indices.contains(index) else { return nil }

        return Binding<Color>(
            get: {
                guard wrappedValue.colors.indices.contains(index) else { return .clear }
                return wrappedValue.colors[index].color
            },
            set: { color in
                editorUpdate { branding in
                    guard branding.colors.indices.contains(index) else { return }
                    branding.colors[index] = BrandColor(color: color)
                }
            }
        )
    }

    func editorRemoveColor(for role: BrowserSpaceBrandColorRole) {
        editorUpdate { branding in
            guard branding.colors.count > 1,
                role.slot == branding.colors.count - 1
            else { return }
            branding.colors.removeLast()
        }
    }

    func editorAddColor(for role: BrowserSpaceBrandColorRole) {
        guard role.slot == wrappedValue.colors.count else { return }
        let next =
            BrandColor.presets.first {
                !wrappedValue.colors.contains($0)
            } ?? wrappedValue.colors.last ?? .ocean
        editorUpdate { $0.colors.append(next) }
    }
}
