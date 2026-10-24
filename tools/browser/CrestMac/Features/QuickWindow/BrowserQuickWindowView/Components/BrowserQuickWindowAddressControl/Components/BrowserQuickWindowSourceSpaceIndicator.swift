import SwiftUI

struct BrowserQuickWindowSourceSpaceIndicator: View {
    let space: BrowserSpaceIdentity?

    var body: some View {
        HStack(spacing: 7) {
            if let space {
                BrowserSpaceSymbolArtwork(space: space, size: 20, lockSize: 5)
            } else {
                Image(systemName: "square.grid.2x2")
            }
            Text(space?.name ?? "Space")
                .lineLimit(1)
        }
        .font(.callout.weight(.semibold))
        .padding(
            .horizontal,
            BrowserQuickWindowLayout.sourceChipHorizontalPadding
        )
        .frame(height: CrestLayout.minimumHitTarget)
        .background(
            CrestColor.hover,
            in: .rect(cornerRadius: CrestRadius.compact, style: .continuous)
        )
        .fixedSize()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Current Quick Window Space")
        .accessibilityIdentifier("quick-window-source-space")
        .accessibilityValue(space?.name ?? "Space")
    }
}

#if DEBUG
    #Preview("Component") {
        BrowserQuickWindowSourceSpaceIndicator(space: BrowserSpaceBrandingPreviewFixture.simpleSpace.identity)
            .padding()
    }
#endif
