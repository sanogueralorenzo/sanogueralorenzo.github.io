import SwiftUI

struct MobileCompactDomainChip: View {
    let url: URL?
    let showToolbar: () -> Void

    var body: some View {
        Button(action: showToolbar) {
            Text(domain)
                .font(.callout.weight(.semibold))
                .lineLimit(1)
                .padding(.horizontal, MobileCompactDomainChipLayout.horizontalPadding)
                .frame(height: MobileCompactDomainChipLayout.visibleHeight)
                .glassEffect(.regular.interactive(), in: .capsule)
        }
        .buttonStyle(.plain)
        .frame(minHeight: MobileCompactDomainChipLayout.minimumHitTarget)
        .contentShape(.rect)
        .padding(.horizontal, MobileCompactDomainChipLayout.outerHorizontalPadding)
        .accessibilityLabel("Show Toolbar")
        .accessibilityValue(domain)
        .accessibilityHint("Expands the browser controls")
        .accessibilityIdentifier("collapsed-domain-chip")
    }

    private var domain: String {
        url?.host() ?? url?.absoluteString ?? "Show Toolbar"
    }
}

#if DEBUG
    #Preview("Component") {
        MobileCompactDomainChip(url: URL(string: "https://crestbrowser.com"), showToolbar: {}).padding()
    }
#endif
