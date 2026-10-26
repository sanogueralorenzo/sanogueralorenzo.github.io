import SwiftUI

struct MobileOnboardingPageActions: View {
    let primaryTitle: String
    let primarySystemImage: String
    let primaryIdentifier: String
    let primaryDisabled: Bool
    let showsActivity: Bool
    let secondaryTitle: String?
    let secondaryIdentifier: String?
    let secondaryAction: (() -> Void)?
    let primaryAction: () -> Void

    var body: some View {
        VStack(spacing: MobileOnboardingLayout.pageActionsSpacing) {
            Button(action: primaryAction) {
                HStack(spacing: MobileOnboardingLayout.primaryActionSpacing) {
                    if showsActivity {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(primaryTitle)
                    if !showsActivity {
                        Image(systemName: primarySystemImage)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .disabled(primaryDisabled)
            .accessibilityIdentifier(primaryIdentifier)

            if let secondaryTitle, let secondaryAction {
                Button(secondaryTitle, action: secondaryAction)
                    .buttonStyle(.plain)
                    .font(.callout.weight(.semibold))
                    .frame(
                        minHeight:
                            MobileOnboardingLayout.secondaryActionMinimumHeight
                    )
                    .crestAccessibilityIdentifier(secondaryIdentifier)
            }
        }
        .frame(maxWidth: MobileOnboardingLayout.pageActionsMaximumWidth)
        .padding(
            .horizontal,
            MobileOnboardingLayout.pageContentHorizontalPadding
        )
        .frame(maxWidth: .infinity)
    }
}

#if DEBUG
    #Preview("Ready and working") {
        @Previewable @State var busy = false
        VStack {
            MobileOnboardingPageActions(
                primaryTitle: "Continue", primarySystemImage: "arrow.right", primaryIdentifier: "preview-continue",
                primaryDisabled: busy, showsActivity: busy, secondaryTitle: "Back", secondaryIdentifier: "preview-back",
                secondaryAction: {}, primaryAction: { busy = true })
            Toggle("Working", isOn: $busy)
        }.padding().frame(width: 360)
    }
#endif
