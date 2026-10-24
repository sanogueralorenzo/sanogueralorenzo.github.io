import SwiftUI

/// The first page: the mark, one line, and what the welcome offers, beside a
/// banner of a Space wearing Crest's own look.
struct BrowserOnboardingWelcomePage: View {
    let action: BrowserOnboardingWelcomeAction
    let hasCompletedSetup: Bool
    let hasDisposableSeedState: Bool
    let continueSetup: () -> Void
    let setUpWithoutCloud: () -> Void
    let openCrest: () -> Void

    private var cloudStatusDetail: String {
        if hasCompletedSetup {
            return String(localized: "Your existing Crest setup is ready.")
        }
        if !hasDisposableSeedState {
            return String(localized: "Your existing Spaces are ready to customize.")
        }
        if action.reportsCloudUnavailable {
            return String(localized: "iCloud is unavailable right now; you can still set up this Mac.")
        }
        return String(localized: "No existing setup was found.")
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 0) {
                column
                    .frame(maxWidth: 560, alignment: .leading)
                    .padding(.leading, 80)
                Spacer(minLength: 60)
                BrowserOnboardingWindowPreview(
                    branding: SpaceHouse.winter.look, symbol: "house.fill", name: String(localized: "Personal")
                ) {
                    BrowserSpaceCrestIcon(branding: SpaceHouse.winter.look, size: 160)
                        .frame(width: 160, height: 160)
                }
                .frame(width: 680, height: 460)
                .padding(.trailing, 100)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            column
                .frame(maxWidth: 560, alignment: .leading)
                .padding(.leading, 80)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }

    private var column: some View {
        VStack(alignment: .leading, spacing: 28) {
            Spacer()
            CrestStartPageMark()
                .frame(width: 84, height: 84)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 14) {
                Text("Welcome to Crest")
                    .font(CrestTypography.display(68))
                    .foregroundStyle(CrestBrandTheme.textDisplay)
                    .accessibilityAddTraits(.isHeader)
                Text("Internet under your colors.")
                    .font(CrestTypography.sans(21))
                    .foregroundStyle(CrestBrandTheme.textDisplay.opacity(0.78))
            }
            BrowserOnboardingWelcomeCallToAction(
                action: action,
                cloudStatusDetail: cloudStatusDetail,
                perform: performAction,
                setUpWithoutCloud: setUpWithoutCloud
            )
            Spacer()
        }
    }

    private func performAction() {
        guard !action.waitsOnCloud else { return }
        if action.opensCrest {
            openCrest()
        } else {
            continueSetup()
        }
    }
}
