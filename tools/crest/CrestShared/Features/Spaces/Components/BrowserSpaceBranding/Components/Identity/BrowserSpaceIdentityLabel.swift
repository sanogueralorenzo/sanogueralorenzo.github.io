import SwiftUI

struct BrowserSpaceIdentityLabel: View {
    let identity: BrowserSpaceIdentity
    var title: String?
    var iconSize: CGFloat = 20

    init(space: some BrowserSpaceIdentifying, title: String? = nil, iconSize: CGFloat = 20) {
        self.init(identity: space.identity, title: title, iconSize: iconSize)
    }

    init(identity: BrowserSpaceIdentity, title: String? = nil, iconSize: CGFloat = 20) {
        self.identity = identity
        self.title = title
        self.iconSize = iconSize
    }

    var body: some View {
        Label {
            Text(title ?? identity.name)
        } icon: {
            BrowserSpaceSymbolArtwork(
                identity: identity,
                size: iconSize,
                lockSize: max(5, iconSize * 0.24)
            )
            .frame(width: iconSize, height: iconSize)
        }
    }
}

#if DEBUG
    #Preview("Space identities") {
        VStack(alignment: .leading, spacing: 20) {
            BrowserSpaceIdentityLabel(space: BrowserSpaceBrandingPreviewFixture.simpleSpace)
            BrowserSpaceIdentityLabel(space: BrowserSpaceBrandingPreviewFixture.crestSpace)
        }.padding()
    }
#endif
