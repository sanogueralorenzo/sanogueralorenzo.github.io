import SwiftUI

struct BrowserSpaceIdentityIcon: View {
    // MARK: - Variables

    let identity: BrowserSpaceIdentity
    var size: CGFloat = 24

    // MARK: - Initializers

    init(space: some BrowserSpaceIdentifying, size: CGFloat = 24) {
        self.init(identity: space.identity, size: size)
    }

    init(identity: BrowserSpaceIdentity, size: CGFloat = 24) {
        self.identity = identity
        self.size = size
    }

    // MARK: - Actions - Drawing

    var body: some View {
        Circle()
            .fill(identity.color.tint.color)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
