import SwiftUI

/// The one `ButtonStyle` Crest draws.
///
/// Built on `ButtonStyle` so keyboard activation, focus, the disabled cascade,
/// and the button accessibility trait remain system-owned.
struct CrestButtonStyle: ButtonStyle {
    let role: CrestButtonRole
    /// Space-owned surfaces can override the role's default colour. Brand chrome
    /// leaves this `nil` and inherits `CrestBrandTheme`.
    var tint: Color?

    func makeBody(configuration: Configuration) -> some View {
        CrestButtonSurface(role: role, tint: tint, configuration: configuration)
    }
}
