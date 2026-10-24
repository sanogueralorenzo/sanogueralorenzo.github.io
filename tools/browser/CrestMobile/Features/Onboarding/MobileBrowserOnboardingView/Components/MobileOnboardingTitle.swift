import SwiftUI

struct MobileOnboardingTitle: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(spacing: MobileOnboardingLayout.titleSpacing) {
            Text(title)
                .font(.title.bold())
                .multilineTextAlignment(.center)
            Text(detail)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: MobileOnboardingLayout.titleMaximumWidth)
    }
}

#if DEBUG
    #Preview("Component") {
        MobileOnboardingTitle(
            title: "A Space for everything", detail: "Keep work, personal browsing, and projects organized."
        ).padding().frame(width: 360)
    }
#endif
