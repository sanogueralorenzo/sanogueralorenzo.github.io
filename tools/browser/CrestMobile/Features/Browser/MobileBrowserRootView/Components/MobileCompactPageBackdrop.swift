import SwiftUI
import UIKit

struct MobileCompactPageBackdrop: View {
    // MARK: - Static Variables

    /// Whether a page stands on its own theme colour rather than the Space's
    /// atmosphere.
    private static let usesPageThemeBackdrop = true

    // MARK: - Variables

    let isStartPage: Bool
    let hasSelectedPage: Bool
    let pageThemeColor: UIColor?
    let underPageBackgroundColor: UIColor?
    let space: SpaceModel?

    var body: some View {
        if Self.usesPageThemeBackdrop,
            !isStartPage,
            hasSelectedPage
        {
            Color(
                uiColor: pageThemeColor
                    ?? underPageBackgroundColor
                    ?? .systemBackground
            )
            .ignoresSafeArea()
        } else {
            BrowserWindowAtmosphere(space: space)
                .ignoresSafeArea()
        }
    }
}
