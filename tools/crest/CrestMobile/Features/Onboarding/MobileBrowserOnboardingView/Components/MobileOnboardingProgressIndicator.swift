import SwiftUI

struct MobileOnboardingProgressIndicator: View {
    let currentIndex: Int?

    var body: some View {
        HStack(spacing: MobileOnboardingLayout.progressSpacing) {
            ForEach(0..<MobileOnboardingLayout.progressStepCount, id: \.self) { index in
                Capsule()
                    .fill(
                        index <= (currentIndex ?? -1)
                            ? Color.accentColor
                            : Color.secondary.opacity(
                                MobileOnboardingLayout.incompleteProgressOpacity
                            )
                    )
                    .frame(height: MobileOnboardingLayout.progressHeight)
            }
        }
        .frame(maxWidth: MobileOnboardingLayout.progressMaximumWidth)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(progressAccessibilityLabel)
        .accessibilityIdentifier(
            BrowserMobileAccessibilityID.progress
        )
    }

    private var progressAccessibilityLabel: String {
        guard let currentIndex else { return "Onboarding introduction" }
        return "Onboarding step \(currentIndex + 1) of \(MobileOnboardingLayout.progressStepCount)"
    }
}

#if DEBUG
    #Preview("Progress states") {
        VStack(spacing: 24) {
            MobileOnboardingProgressIndicator(currentIndex: 0)
            MobileOnboardingProgressIndicator(currentIndex: 2)
            MobileOnboardingProgressIndicator(currentIndex: nil)
        }.padding()
    }
#endif
