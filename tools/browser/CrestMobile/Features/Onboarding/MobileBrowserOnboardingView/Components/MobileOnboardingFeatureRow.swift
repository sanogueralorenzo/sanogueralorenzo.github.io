import SwiftUI

struct MobileOnboardingFeatureRow: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: MobileOnboardingLayout.featureRowSpacing) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.tint)
                .frame(
                    width: MobileOnboardingLayout.featureSymbolSize,
                    height: MobileOnboardingLayout.featureSymbolSize
                )
            VStack(
                alignment: .leading,
                spacing: MobileOnboardingLayout.featureRowTextSpacing
            ) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, MobileOnboardingLayout.featureRowVerticalPadding)
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
    #Preview("Component") {
        MobileOnboardingFeatureRow(
            symbol: "square.grid.2x2.fill", title: "Separate Spaces",
            detail: "Give each part of your day its own tabs and identity."
        ).padding().frame(width: 360)
    }
#endif
