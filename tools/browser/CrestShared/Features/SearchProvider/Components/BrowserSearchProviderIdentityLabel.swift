import SwiftUI

/// How large a search provider's icon and name sit, by input size.
struct BrowserSearchProviderIdentityLabelLayout: Hashable, Sendable {
    // MARK: - Static Variables

    static let compact = BrowserSearchProviderIdentityLabelLayout(
        name: "compact", iconSize: 20, spacing: 4, verticalPadding: 0)
    static let touch = BrowserSearchProviderIdentityLabelLayout(
        name: "touch", iconSize: 28, spacing: 8, verticalPadding: 4)

    #if os(macOS)
        static let platformDefault = compact
    #else
        static let platformDefault = touch
    #endif

    // MARK: - Variables

    let name: String
    let iconSize: CGFloat
    let spacing: CGFloat
    let verticalPadding: CGFloat

    // MARK: - Initializers

    private init(name: String, iconSize: CGFloat, spacing: CGFloat, verticalPadding: CGFloat) {
        self.name = name
        self.iconSize = iconSize
        self.spacing = spacing
        self.verticalPadding = verticalPadding
    }

    // MARK: - Actions - Identity

    static func == (
        lhs: BrowserSearchProviderIdentityLabelLayout, rhs: BrowserSearchProviderIdentityLabelLayout
    ) -> Bool {
        lhs.name == rhs.name
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }
}

struct BrowserSearchProviderIdentityLabel: View {
    let provider: SearchProvider
    var profileID: UUID? = nil
    var title: String? = nil
    var layout: BrowserSearchProviderIdentityLabelLayout = .platformDefault

    var body: some View {
        HStack(spacing: layout.spacing) {
            BrowserSearchProviderIcon(
                provider: provider,
                profileID: profileID,
                size: layout.iconSize
            )
            Text(title ?? provider.title)
        }
        .padding(.vertical, layout.verticalPadding)
    }
}
