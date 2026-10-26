import SwiftUI

/// Forwards to `CrestTypography` so the wizard and the rest of the app share
/// one type scale. Kept as a name because the wizard's call sites are
/// hand-composed.
enum BrowserOnboardingTypography {
    static func display(_ size: CGFloat) -> Font {
        CrestTypography.display(size)
    }

    static func sans(
        _ size: CGFloat,
        weight: Font.Weight = .regular
    ) -> Font {
        CrestTypography.sans(size, weight: weight)
    }
}
