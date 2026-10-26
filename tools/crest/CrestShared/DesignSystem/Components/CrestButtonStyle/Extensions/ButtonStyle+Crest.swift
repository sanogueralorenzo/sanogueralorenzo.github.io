import SwiftUI

extension ButtonStyle where Self == CrestButtonStyle {
    static var crestPrimary: CrestButtonStyle {
        CrestButtonStyle(role: .primary)
    }

    static func crestPrimary(tint: Color) -> CrestButtonStyle {
        CrestButtonStyle(role: .primary, tint: tint)
    }

    static var crestSecondary: CrestButtonStyle {
        CrestButtonStyle(role: .secondary)
    }

    static var crestTertiary: CrestButtonStyle {
        CrestButtonStyle(role: .tertiary)
    }

    static func crestTertiary(tint: Color) -> CrestButtonStyle {
        CrestButtonStyle(role: .tertiary, tint: tint)
    }

    static var crestDestructive: CrestButtonStyle {
        CrestButtonStyle(role: .destructive)
    }

    static func crestIcon(
        tint: Color? = nil,
        diameter: CGFloat = CrestButtonMetrics.iconDiameter,
        isProminent: Bool = false
    ) -> CrestButtonStyle {
        CrestButtonStyle(
            role: .icon(diameter: diameter, isProminent: isProminent),
            tint: tint
        )
    }
}
