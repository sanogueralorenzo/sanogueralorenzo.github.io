import SwiftUI

/// A tab with no page in memory as the address bar's swipe slides it in: its
/// icon and title over the Space's backdrop. Touching the bar never loads a
/// tab; the one a swipe lands on loads once it is shown.
struct MobileTabSwipePlaceholder: View {
    let tab: TabStateModel
    let space: SpaceModel
    let favicons: FaviconAssets
    /// The page area's chrome, which the icon and title stay clear of.
    let bottomChromeHeight: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 12) {
            TabStateFaviconView(tab: tab, favicons: favicons, profileID: space.profileID, size: 40)
            Text(tab.shownTitle)
                .font(.headline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, bottomChromeHeight)
        .background {
            BrowserWindowAtmosphere(space: space)
                .ignoresSafeArea()
        }
        .environment(\.colorScheme, space.settings.look.colorScheme(over: colorScheme))
    }
}
