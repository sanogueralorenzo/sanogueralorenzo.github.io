import SwiftUI

/// The bottom of a page: Back, or Close where Back leaves setup, on the left,
/// and what the page offers on the right.
struct BrowserOnboardingFooter<Trailing: View>: View {
    /// What Back does, or nil for a page that offers no way back.
    let back: BrowserOnboardingBackAction?
    var isBackDisabled = false
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack {
            if let back {
                Button(back.closes ? "Close" : "Back", action: back.action)
                    .buttonStyle(.crestSecondary)
                    .disabled(isBackDisabled)
                    .accessibilityIdentifier(back.closes ? "onboarding-close" : "onboarding-back")
            }
            Spacer()
            trailing
        }
        .controlSize(.large)
        .padding(.horizontal, BrowserOnboardingStageMetrics.inset)
        .padding(.bottom, BrowserOnboardingStageMetrics.inset - 8)
    }
}

/// A page's one serif line.
struct BrowserOnboardingHeadline: View {
    let text: LocalizedStringKey

    init(_ text: LocalizedStringKey) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(CrestTypography.display(BrowserOnboardingStageMetrics.headlineSize))
            .foregroundStyle(CrestBrandTheme.textDisplay)
            .accessibilityAddTraits(.isHeader)
    }
}

/// The primary button that carries a page forward, with its arrow.
struct BrowserOnboardingContinueButton: View {
    let title: Text
    let action: () -> Void

    init(_ title: LocalizedStringKey = "Continue", action: @escaping () -> Void) {
        self.init(Text(title), action: action)
    }

    init(_ title: Text, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                title
                Image(systemName: "arrow.right")
            }
            .frame(minWidth: 120)
        }
        .buttonStyle(.crestPrimary)
        .keyboardShortcut(.defaultAction)
    }
}
